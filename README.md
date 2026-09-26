# raymart

Sistema de comercio electrónico **distribuido**, escrito en
[raylang](https://github.com/ray-language/raylang): cuatro APIs con **arquitectura hexagonal**
(products, cart, orders, payment), cada una con su propia base de datos, detrás de un gateway,
hablando entre sí por `rpc` y **gRPC**, y coordinadas de forma asíncrona por una cola persistente.

> En construcción: el plan y el estado de cada hito están abajo.

| Pieza | Qué es | Datos / protocolo |
|---|---|---|
| **raygate** | gateway: JWT, rate limit, breaker, trazas W3C | HTTP |
| **products** | catálogo y stock | PostgreSQL · HTTP + rpc |
| **cart** | carrito por usuario con TTL | raykv (protocolo Redis) · HTTP |
| **orders** | pedidos y saga de checkout | MySQL · HTTP + rayq |
| **payment** | intents y cobros simulados | MongoDB · gRPC + rayq |
| **rayq** | cola de trabajos persistente (at-least-once, DLQ) | rpc |
| **raykv** | almacén clave-valor RESP | Redis |
| **raywatch** | dashboard de salud | HTTP/SSE |

Todo corre en contenedores con `docker compose`; las apps reutilizadas de `ray-apps`
(raygate, rayq, raykv, raywatch) y los servicios nuevos se compilan como **binarios nativos**.
