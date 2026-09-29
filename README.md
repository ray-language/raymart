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
make bench   # carga creciente hasta 64 usuarios concurrentes, con invariantes (perf/README.md)
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
| **bench** | generador de carga (perfil `bench`) | HTTP keep-alive · rpc | nuevo (`tools/raymart`) |

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
contra MySQL en producción y contra memoria en los tests. (Hasta raylang 1.27.12 un campo
`dyn Trait` no compilaba; los genéricos, además, resuelven el adaptador en compilación.)

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
| `check-release-it` | los tests de integración con la release, desde un contenedor |
| `check-native` | los tests unitarios sobre binarios nativos (`ray test --native`), con la release |
| `e2e` | escenarios de punta a punta a través del gateway (el CLI nativo, dentro de la red) |
| `chaos` | resiliencia: payment caído durante un checkout |
| `chaos-db` | resiliencia: reinicia las cuatro bases de datos; el primer e2e de después debe pasar entero |
| `trace ID=…` · `log-stats` | raylogs sobre los logs JSON |
| `token USER_ID=…` | un JWT de desarrollo |
| `bench` | prueba de carga: 1 → 8 → 32 → 64 usuarios virtuales × 15 s por escenario, invariantes bajo concurrencia, informe en `perf/results/` ([perf/README.md](perf/README.md)) |
| `bench-quick` | la misma prueba, corta (1 y 16 VUs × 5 s) |

## Estado

| Qué | Verificado |
|---|---|
| Tests unitarios | common 7 · grpc 12 · products 14 · cart 7 · orders 15 · payment 10 · tools 10 — con la release 1.27.15, en VM y en nativo |
| Integración | PostgreSQL 18: 6 (seis pedidos por la última unidad: gana uno; conexiones matadas por el servidor, también en una transacción) · raykv: 2 (con TTL) · MySQL 8.4: 4 (pedido + outbox atómicos; conexiones matadas) · MongoDB 8: 2 (cinco CreateIntent concurrentes: un intent) |
| gRPC | contrato payment en proceso, sobre `net/grpc_server` y `net/grpc_conn` (net 0.5) |
| Docker | las 11 piezas sanas; `make e2e` 19/19; `make chaos` pendiente → pagado; `make chaos-db` 19/19 tras reiniciar las bases; raywatch 11/11 en verde |
| Carga | 29 600 lecturas/s directas y 16 900 por el gateway, ~140 compras/s de punta a punta con 64 usuarios; 0 errores y todas las invariantes ([perf/README.md](perf/README.md)) |

## Notas

- **Pools de conexiones** en los adaptadores de salida, los de las librerías: `postgres.pool`,
  `mysql.pool`, `mongo.pool` (db 0.2), `redis.pool` y el `net/pool` genérico para el cliente
  gRPC (net 0.5); raygate usa `http.pool`. Las fibras no comparten heap, así que las conexiones
  viajan por un canal acotado: cada operación toma una, la devuelve, o la cierra si el cable
  falló. Una conexión reutilizada que el servidor cerró (un reinicio) se reemplaza y la
  operación idempotente se repite una vez. Las transacciones van por `pool_tx`, que reintenta
  un BEGIN fallido en una conexión caducada pero nunca el cuerpo. Tamaños: `PG_POOL_SIZE`,
  `MYSQL_POOL_SIZE`, `MONGO_POOL_SIZE`, `RAYKV_POOL_SIZE`, `RPC_POOL_SIZE`.
- **gRPC** sin librería propia: payment sirve con `net/grpc_server` y orders llama con
  `net/grpc_conn` (net 0.5), el mismo código que antes vivía en `libs/grpc`.
- **El estado vive en las bases de datos.** Los handlers gRPC y HTTP reciben una *copia* de lo
  que capturan (por conexión), así que nada en memoria del proceso es estado compartido.
- **Toolchain.** Las imágenes usan la release 1.27.19 (cada `ray.toml` la exige con
  `[package] raylang`); `make check-release` y
  `make check-release-it` corren los tests con ella en un contenedor, así que no dependen del
  toolchain del host. `make test` y `make test-it` usan el `ray` local.
- El JWT de desarrollo (`raymart-dev-secret-change-me`) está en `docker-compose.yml` y en
  `config/raygate.toml`: cámbialo en ambos (o `RAYMART_JWT_SECRET` + la config del gateway).

## Hallazgos de dogfood

Los hallazgos sobre raylang que salieron de este proyecto están en
[`ray-apps/RAYLANG-FINDINGS.md`](../RAYLANG-FINDINGS.md), sección raymart.
