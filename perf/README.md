# Rendimiento de raymart

`make bench` somete el sistema a carga creciente, comprueba que las reglas de negocio
aguantan la concurrencia y deja un informe en `perf/results/<fecha>/`. Hay dos corridas de
referencia: la [línea base](baseline.md) (hito 8, el diagnóstico) y
[after-pools.md](after-pools.md) (hito 9, tras arreglar lo diagnosticado).

```bash
make up            # el sistema arriba
make bench         # ~15 min: 1 → 8 → 32 → 64 VUs × 15 s por escenario
make bench-quick   # ~3 min: 1 y 16 VUs × 5 s
make bench ARGS="--scenarios purchase,drain --stages 16,64 --duration 30"
```

## Cómo se mide

- **Generador nativo dentro de la red de compose** (`tools/raymart`, servicio `bench`). No pasa
  por el reenvío de puertos de Docker Desktop, llega directo a products (para aislar el coste
  del gateway) y a su puerto rpc (para reponer stock).
- **Modelo cerrado**: cada usuario virtual (una fibra con su usuario, su JWT y **una conexión
  keep-alive**) envía la siguiente petición cuando llega la respuesta. Las latencias se guardan
  todas, en µs: los percentiles son exactos, no estimados.
- **Solo cuentan como rendimiento las respuestas correctas** (`ok/s`); los errores se cuentan
  aparte, por código. Tras un 503 o un error de red el VU espera 100 ms, como un cliente real, en
  vez de girar sobre un breaker abierto.
- **Tres fuentes cruzadas por etapa**: el reloj del generador, el histograma de raygate
  (`/metrics`, tiempo de upstream por ruta, antes/después) y `docker stats` de cada contenedor
  (CPU y memoria, alineados con la ventana de la etapa). En la saga, además, la profundidad de
  las colas de rayq (`payment.jobs`, `payment.results`), muestreada cada 250 ms.
- **Etapas aisladas**: entre escenarios, y tras cualquier etapa con errores, el bench espera 65 s.
  Los sockets cerrados retienen su puerto efímero 60 s (`TIME_WAIT`), y sin la pausa una etapa
  hereda los puertos agotados de la anterior (ver el diagnóstico).
- **Gateway sin rate limit** durante la prueba (`config/raygate.bench.toml`). El generador es una
  sola IP, y los límites por IP se medirían a sí mismos; el script restaura la configuración
  normal al terminar, pase lo que pase.

## Escenarios

| escenario | qué hace | qué ejercita |
|---|---|---|
| `browse` | `GET /api/products` y `/api/products/:id` por el gateway | raygate → products → PostgreSQL |
| `browse-direct` | lo mismo, directo a products | la diferencia con `browse` es el coste del gateway |
| `cart` | añadir, leer y quitar una línea del carrito | raygate → cart → raykv, y rpc a products en cada alta |
| `purchase` | carrito → checkout → sondear el pedido (cada 200 ms) hasta que la saga lo resuelve; 1 de cada 10 tarjetas se rechaza | la saga completa: MySQL + outbox → gRPC → payment/Mongo → rayq → worker → rayq → consumidor → products; y la compensación |
| `drain` | 64 VUs compran el mismo producto hasta agotarlo | concurrencia sobre el stock: la reserva `FOR UPDATE` |

## Invariantes (el bench falla si alguna se rompe)

- **Conservación del stock** en `purchase`: stock inicial − unidades pagadas = stock final. Los
  pedidos rechazados devuelven su reserva.
- **Ningún pedido colgado**: todos se resuelven (pagado o cancelado) en menos de 60 s.
- **Nunca se vende de más** en `drain`: se aceptan exactamente tantas unidades como había en
  stock, todas se pagan, el producto termina en 0 y todos los VUs reciben el 409 de agotado.
  Después se devuelve el stock original.

## Línea base (hito 8, 26 sep 2026)

Apple M3 Pro, Docker Desktop con 6 CPUs y 15,6 GiB; todo en nativo con raylang 1.27.11.
Informe completo: [baseline.md](baseline.md) (y [baseline.json](baseline.json)).

| escenario | 1 VU | 8 VUs | 32 VUs | 64 VUs |
|---|---|---|---|---|
| `browse` (ok/s · p99) | 244 · 6,8 ms | 705 · 20,6 ms | 761 · 72,5 ms | 266 · 168 ms, **58 % errores** |
| `browse-direct` | 271 · 6,8 ms | 856 · 18,7 ms | 866 · 68,6 ms | 43 · 137 ms, **93 % errores** |
| `cart` | 301 · 13,4 ms | 694 · 41,5 ms | 130 · 104 ms, **67 % errores** | 1038 · 334 ms (tras la pausa) |
| `purchase` (compras/s · hasta pagado p50) | 1,5 · 0,62 s | 9,1 · 0,83 s | 25,3 · 1,23 s | 26,5 · 2,28 s |
| `drain` | | | | 500 unidades en 24,5 s: exactas |

**Invariantes: todas se cumplen.** El stock se conserva en cada etapa (también con pedidos
rechazados y compensados), ningún pedido se queda colgado, y con 64 compradores concurrentes
se venden exactamente las 500 unidades: ni una más.

## Diagnóstico

### 1. Una conexión nueva por operación agota los puertos efímeros (el cuello principal)

Los adaptadores abren una conexión por operación (products → PostgreSQL, cart → raykv,
orders → MySQL, payment → MongoDB), y raygate abre otra por cada petición que reenvía. Cada
socket cerrado retiene su puerto efímero 60 s en `TIME_WAIT`, y un contenedor tiene 28 232
(32768–60999). El techo sostenido es **~470 conexiones nuevas por segundo** entre cada par de
contenedores. products sirve ~800 peticiones/s, así que agota los puertos en cuanto la carga
dura más de medio minuto. Los logs lo confirman: `Cannot assign requested address (os error 99)`.

- El colapso es **acumulativo**: `cart × 64` rinde 1 038 ok/s porque empieza tras una pausa de
  65 s con los puertos libres, mientras que `cart × 32`, justo después de `cart × 8`, falla el
  67 %.
- Cuando products empieza a fallar, el **circuit breaker** de raygate (5 fallos, 10 s) se abre
  y responde 503 al instante. Es el comportamiento correcto: protege al servicio. En la línea
  base cortó 5 542 peticiones en `browse × 64`.
- **El handshake también cuesta CPU.** Para ~800 lecturas triviales por segundo, products y
  PostgreSQL consumen 2–2,5 núcleos cada uno. PostgreSQL crea un proceso por conexión y la
  autentica con SCRAM-SHA-256 (PBKDF2 de 4 096 iteraciones, en ambos extremos).
- Con 8–32 VUs el catálogo ya está **saturado** en ~760–870 ok/s: más usuarios solo suben la
  latencia (p50 de 11 ms a 41 ms).

### 2. La saga está limitada por el relé del outbox (~25 compras/s)

Entre 32 y 64 VUs el rendimiento de `purchase` se queda en ~25–26 compras/s, mientras el
tiempo hasta `paid` se duplica (p50 de 1,2 s a 2,3 s). La cola `payment.jobs` tiene un pico de
**exactamente 20**, que es el tamaño de lote del relé, y no crece más: el worker de payment y
el consumidor de orders dan abasto. El relé entrega 20 mensajes y duerme 500 ms, con una
conexión gRPC nueva por mensaje: 20 / (0,5 s + el tiempo del lote) ≈ 25/s. A eso se suma el
tiempo mínimo de un pedido (~0,6 s con 1 VU), que es la espera media del tick del relé más los
300 ms de sondeo en vacío de los dos consumidores.

### 3. El coste del gateway

Con 1 VU, raygate añade ~0,4 ms por petición (4,1 ms frente a 3,7 ms). Con 32 VUs recorta el
techo un ~12 % (761 frente a 866 ok/s), porque también abre una conexión por petición hacia
el upstream.

## Hito 9: pools de conexiones, keep-alive y una saga sin esperas

Cada cambio se midió por separado con `scripts/bench.sh --scenarios …` antes de la corrida
completa ([after-pools.md](after-pools.md)).

| escenario, 64 VUs salvo indicación | línea base | hito 9 | |
|---|---|---|---|
| `browse-direct` (32 VUs) | 866 ok/s · p99 68,6 ms | **29 630 ok/s · p99 3,6 ms** | 34× |
| `browse` por raygate | 266 ok/s, 58 % errores | **14 906 ok/s · p99 12,1 ms**, 0 errores | |
| `cart` | 1 038 ok/s · p99 334 ms | **2 037 ok/s · p99 71 ms** | 2× |
| `purchase` | 26,5 compras/s · hasta pagado p50 2,28 s | **145,8 compras/s · p50 0,42 s** | 5,5× |
| `purchase` con 1 VU, hasta pagado p50 | 0,62 s | **0,21 s** | |
| `drain` de 500 unidades | 24,5 s | **3,6 s** | 6,8× |
| errores en toda la corrida | 18 595 (y 3 pausas de 65 s) | **0** | |

Las invariantes siguen cumpliéndose en todas las etapas.

### Qué cambió

1. **Pools de conexiones en los cuatro adaptadores** (PostgreSQL, MySQL, MongoDB, raykv). Es
   el patrón de `rpc.pool`: un canal acotado de slots por el que viajan las propias conexiones
   (`libs/common/pool.ray` lo documenta). Las fibras no comparten heap, pero un socket pasado
   por un canal es el mismo en todas. Un error del cable cierra la conexión y deja el slot
   vacío, así que el pool se recupera solo tras una caída. Es un cambio solo de adaptadores: el
   hexágono no se tocó. Tamaños por variable de entorno (`PG_POOL_SIZE`, `MYSQL_POOL_SIZE`,
   `MONGO_POOL_SIZE`, `RAYKV_POOL_SIZE`, `RPC_POOL_SIZE`).
2. **raygate reutiliza conexiones keep-alive** hacia cada upstream (ray-language/raygate#4,
   `[server] upstream_pool`). Con 1 VU el catálogo por el gateway pasó de 1 525 a 2 282 ok/s.
3. **Saga sin esperas**: el relé encadena lotes mientras vengan llenos (tick de 100 ms, lotes
   de 50) sobre una conexión gRPC reutilizada; orders aplica resultados con 4 consumidores
   concurrentes y payment cobra con 4 workers, porque ambos pasos son idempotentes. Los
   consumidores en vacío sondean cada 100 ms en vez de 300.

### Lo que se encontró por el camino

- **Un pool de 16 conexiones a raykv para 64 peticiones concurrentes** hundía `cart × 64` (958
  ok/s, p99 807 ms): las fibras esperaban turno. Con 64, 2 252 ok/s y p99 73 ms.
- **`db/mysql` nunca compacta su búfer de lectura.** Con conexiones reutilizadas, orders pasó de
  33 MiB a 1,7 GiB en un minuto, con la CPU al 350 %, y la saga cayó a 40 compras/s. Se esquiva
  reiniciando el búfer al devolver la conexión (RAYLANG-FINDINGS #72); con eso orders se queda
  en ~45 MiB y la saga sube a 146/s.
- **El código de pool genérico no compila en nativo** (RAYLANG-FINDINGS #71). Pasaba los tests
  en la VM, pero la imagen de products no se construía y la primera medición «con pools» era en
  realidad de la imagen vieja. Desde entonces, cada medición va precedida de un build comprobado.

### Y la resiliencia

Un pool guarda conexiones que pueden caducar: tras reiniciar una base de datos, cada conexión
del pool fallaba una vez delante de un usuario (16 en products, 64 en cart), porque el canal es
FIFO y el pool solo descartaba una conexión después de fallar. Ahora una conexión **reutilizada**
que falla por el cable se cierra y la operación se repite una vez en una conexión nueva (como
hace `net/http` con keep-alive). Solo se hace con operaciones idempotentes: el alta de un pedido
solo se repite si la transacción ni siquiera empezó, y `restock` nunca. Los tests de integración
de PostgreSQL y MySQL matan las conexiones desde el servidor y fallan sin el reintento. `make
chaos-db` reinicia las cuatro bases y exige que el siguiente e2e pase entero (19/19, tres veces
seguidas). El rendimiento no cambió.

### Límites que quedan

- **Lecturas directas**: ~29 600 ok/s a 32 VUs, con products en ~2,3 núcleos y PostgreSQL en
  ~1,4. Es el techo de la máquina (6 CPUs para Docker) más que del diseño.
- **Por el gateway**: ~15 000 ok/s, con raygate en ~1,4 núcleos. Cada petición pasa dos veces
  por su actor de control (admisión y métricas); es el siguiente sitio donde mirar.
- **Carrito**: ~2 300 ok/s, con cart, raygate y raykv a ~1 núcleo cada uno. Un alta hace un rpc
  a products y dos operaciones en raykv.
- **Saga**: sigue escalando a 64 VUs (145,8 compras/s, colas con pico de 34/31) y ya está
  limitada por la latencia: ~0,2 s por pedido, con el sondeo del cliente cada 200 ms incluido.
