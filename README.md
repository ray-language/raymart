# raymart

Sistema de comercio electrónico **distribuido**, escrito en
[raylang](https://github.com/ray-language/raylang): cuatro APIs con **arquitectura hexagonal**
(products, cart, orders, payment), cada una con su propia base de datos, detrás de un gateway,
hablando entre sí por **rpc** y **gRPC**, y coordinadas de forma asíncrona por una cola
persistente. Todo corre en contenedores con `docker compose`, compilado a **binarios nativos**.

```bash
make up      # construye y levanta todo; gateway en http://127.0.0.1:8088, dashboard en :8091
make e2e     # 19 comprobaciones de punta a punta a través del gateway
make chaos   # checkout con payment caído: el pedido espera y se paga cuando vuelve
```

## Arquitectura

```
                         cliente (HTTP + Bearer JWT)
                                   │ :8088
                          ┌────────▼────────┐
                          │     raygate     │  JWT · rate limit · breaker · trace W3C · /metrics
                          └─┬──────┬──────┬─┘
             /api/products  │      │      │  /api/orders · /api/payments
                   ┌────────┘  /api/cart  └────────────────────┐
                   ▼               ▼                           ▼
             ┌──────────┐    ┌──────────┐   rpc          ┌──────────┐
             │ products │◄───│   cart   │◄──cart.get─────│  orders  │
             │PostgreSQL│◄───┴──rpc─────┘   cart.clear   │  MySQL   │
             │          │◄─────────────products.reserve──│ + outbox │
             └──────────┘       commit / release         └────┬─────┘
                                                              │ gRPC CreateIntent
                                                              ▼  (relay del outbox)
            ┌──────────┐  payment.results  ┌──────────┐ ┌──────────┐
            │  orders  │◄──────────────────│   rayq   │◄│ payment  │
            │ consumer │                   │(cola WAL)│ │ MongoDB  │
            └──────────┘                   └────┬─────┘ └────▲─────┘
                                                └payment.jobs┘ (worker de cobro)

    raykv: carritos (protocolo Redis, con TTL)   raywatch: salud de las 11 piezas (:8091)
    raylogs: consulta de los logs JSON (`make trace`, `make log-stats`)
```

| Pieza | Papel | Datos · protocolos | Origen |
|---|---|---|---|
| **raygate** | gateway | HTTP | ray-apps, binario nativo |
| **products** | catálogo y stock | PostgreSQL 18 · HTTP + rpc | nuevo |
| **cart** | carrito por usuario | raykv · HTTP + rpc | nuevo |
| **orders** | pedidos y saga del checkout | MySQL 8.4 LTS · HTTP · cliente gRPC · rayq | nuevo |
| **payment** | intents y cobros | MongoDB 8 · gRPC + HTTP · rayq | nuevo |
| **rayq** | cola persistente at-least-once con DLQ | rpc | ray-apps, binario nativo |
| **raykv** | clave-valor RESP | Redis | ray-apps, binario nativo |
| **raywatch** | dashboard de salud | HTTP/SSE | ray-apps, binario nativo |
| **raylogs** | análisis de logs (perfil `tools`) | stdin | ray-apps, binario nativo |

## Arquitectura hexagonal

Los cuatro servicios siguen la misma forma:

```
services/<servicio>/src/
  domain/        entidades y reglas puras · ports.ray: los puertos (traits)
  application/   casos de uso, genéricos sobre los puertos
  adapters/
    inbound/     HTTP (web), rpc, gRPC, consumidores de rayq — llaman a los casos de uso
    outbound/    PostgreSQL / MySQL / MongoDB / raykv, clientes rpc y gRPC, y los dobles en
                 memoria de los tests
  main.ray       raíz de composición: lee la configuración y conecta adaptadores con puertos
```

Los puertos son traits y los casos de uso son genéricos sobre ellos
(`Orders<R: OrderRepository, C: CartGateway, I: Inventory, P: Payments>`): el mismo código corre
contra MySQL en producción y contra memoria en los tests. (Un campo `dyn Trait` en un struct no
compila en raylang 1.27.11; los genéricos sí, en VM y en nativo.)

## La saga del checkout

1. `POST /api/orders {card_last4}` → orders lee el carrito (rpc), **reserva el stock** en products
   (todo o nada, idempotente por pedido, con los precios del catálogo) y guarda el pedido
   **y** su mensaje `payment.requested` en **una sola transacción** de MySQL (outbox
   transaccional). Vacía el carrito y responde **202** `pending_payment`. Si el pedido no puede
   guardarse, libera la reserva (compensación).
2. El **relé del outbox** entrega la petición a payment por **gRPC** (`CreateIntent`,
   idempotente por pedido). Si payment no responde, reintenta en orden sin perder nada; si la
   rechaza de forma definitiva, cancela ese pedido y sigue (ningún mensaje venenoso bloquea la
   cola).
3. payment guarda el intent (índice único por pedido en MongoDB) y encola el cobro en rayq; su
   **worker** cobra (simulador determinista) y publica el resultado en `payment.results`.
4. El **consumidor** de orders aplica el resultado: pagado → confirma la reserva → `paid`;
   rechazado → devuelve el stock → `cancelled`. Idempotente; si products no responde, *nack* y
   rayq reintenta.

Tarjetas de prueba (últimos 4 dígitos): `0002` rechazada, `0003` fondos insuficientes, `0004`
error del procesador (se reintenta), cualquier otra aprobada.

Cada petición lleva un `traceparent` W3C de punta a punta (gateway → HTTP → rpc → gRPC → mensajes
de la cola): `make trace ID=<trace_id>` reúne sus líneas de los cuatro servicios.

## API (a través del gateway, `http://127.0.0.1:8088`)

| Método y ruta | Auth | Qué hace |
|---|---|---|
| `GET /api/products`, `GET /api/products/:id` | — | catálogo |
| `GET /api/cart` | JWT | el carrito |
| `POST /api/cart/items` `{product_id, qty}` | JWT | añade unidades (precio del catálogo) |
| `PUT /api/cart/items/:id` `{qty}` · `DELETE /api/cart/items/:id` · `DELETE /api/cart` | JWT | cambia, quita, vacía |
| `POST /api/orders` `{card_last4}` | JWT | checkout → 202 |
| `GET /api/orders`, `GET /api/orders/:id` | JWT | pedidos propios |
| `GET /api/payments/:id` | JWT | pago propio |

```bash
TOKEN=$(make -s token USER_ID=ada)
curl -s -X POST localhost:8088/api/cart/items -H "Authorization: Bearer $TOKEN" -d '{"product_id":5,"qty":2}'
curl -s -X POST localhost:8088/api/orders     -H "Authorization: Bearer $TOKEN" -d '{"card_last4":"4242"}'
```

Errores con una sola forma: `{"error": {"code": "out_of_stock", "message": "…"}}`
(`not_found` 404, `invalid` 400, `out_of_stock`/`conflict` 409, `unauthorized` 401,
`unavailable` 503).

## Tareas

| `make …` | Qué hace |
|---|---|
| `up` / `down` / `ps` / `logs` | el sistema en Docker (los volúmenes de datos se conservan) |
| `test` | tests unitarios de todos los proyectos raylang (sin contenedores) |
| `test-it` | tests de integración de los adaptadores contra las bases en Docker |
| `check-release` | compila y testea todo con la **release** de raylang que usan las imágenes |
| `e2e` | escenarios de punta a punta a través del gateway |
| `chaos` | resiliencia: payment caído durante un checkout |
| `trace ID=…` · `log-stats` | raylogs sobre los logs JSON |
| `token USER_ID=…` | un JWT de desarrollo |

## Estado

| Qué | Verificado |
|---|---|
| Tests unitarios | common 7 · grpc 12 · products 10 · cart 7 · orders 14 · payment 10 — con el toolchain local y con la release 1.27.11 |
| Integración | PostgreSQL 18: 3 (seis pedidos por la última unidad: gana uno) · raykv: 2 (con TTL) · MySQL 8.4: 3 (pedido + outbox atómicos) · MongoDB 8: 2 (cinco CreateIntent concurrentes: un intent) |
| gRPC | contrato payment en proceso; interop con `grpcurl` (librería) |
| Docker | las 11 piezas sanas; `make e2e` 19/19; `make chaos` pendiente → pagado; raywatch 11/11 en verde |

## Notas

- **Una conexión de base de datos por operación.** Las fibras que atienden peticiones no
  comparten heap; una conexión compartida entre ellas se corrompería.
- **El estado vive en las bases de datos.** Los handlers gRPC y HTTP reciben una *copia* de lo
  que capturan (por conexión), así que nada en memoria del proceso es estado compartido.
- **`libs/mongodb`** es una copia parcheada del cliente MongoDB de raylang (`db` 0.1.0): la
  original no puede autenticarse contra MongoDB 6 o posterior (verificado con 8.3). Se elimina cuando `db` publique el arreglo.
- **Toolchain.** Las imágenes usan la release 1.27.11; `make check-release` garantiza que el
  código no dependa de funciones aún no publicadas del toolchain local.
- El JWT de desarrollo (`raymart-dev-secret-change-me`) está en `docker-compose.yml` y en
  `config/raygate.toml`: cámbialo en ambos (o `RAYMART_JWT_SECRET` + la config del gateway).

## Hallazgos de dogfood

Los hallazgos sobre raylang que salieron de este proyecto están en
[`ray-apps/RAYLANG-FINDINGS.md`](../RAYLANG-FINDINGS.md), sección raymart.
