# raymart — benchmark

Started 2026-09-26T08:22:41Z · stages of 1 → 8 → 32 → 64 virtual users × 15 s · closed model (each VU waits for its answer) · keep-alive connections · load generator: native raylang, inside the compose network.

## Overview

| scenario | VUs | throughput and latency |
|---|---:|---|
| browse | 1 | 2281.8 ok/s · worst p99 1.8 ms · no errors |
| browse | 8 | 7723.8 ok/s · worst p99 3.3 ms · no errors |
| browse | 32 | 13088.4 ok/s · worst p99 6.3 ms · no errors |
| browse | 64 | 14905.7 ok/s · worst p99 12.1 ms · no errors |
| browse-direct | 1 | 5056.0 ok/s · worst p99 1.0 ms · no errors |
| browse-direct | 8 | 18757.0 ok/s · worst p99 2.2 ms · no errors |
| browse-direct | 32 | 29629.9 ok/s · worst p99 3.6 ms · no errors |
| browse-direct | 64 | 27738.2 ok/s · worst p99 8.2 ms · no errors |
| cart | 1 | 651.7 ok/s · worst p99 5.8 ms · no errors |
| cart | 8 | 1767.5 ok/s · worst p99 13.6 ms · no errors |
| cart | 32 | 2293.1 ok/s · worst p99 35.0 ms · no errors |
| cart | 64 | 2036.9 ok/s · worst p99 71.3 ms · no errors |
| purchase | 1 | 4.4 purchases/s · to paid p50 205.3 ms, p99 409.8 ms |
| purchase | 8 | 36.9 purchases/s · to paid p50 206.0 ms, p99 409.5 ms |
| purchase | 32 | 99.1 purchases/s · to paid p50 232.2 ms, p99 450.6 ms |
| purchase | 64 | 145.8 purchases/s · to paid p50 420.5 ms, p99 628.3 ms |
| drain | 64 | 500 units sold out in 3.6 s (139.1 orders/s) |

Invariants: all held ✓

## browse

`GET /api/products` and `GET /api/products/:id` through raygate (PostgreSQL reads).

| VUs | step | ok/s | ok | errors | mean ms | p50 | p90 | p95 | p99 | max |
|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `products.list` | 1140.9 | 17114 | 0 | 0.4 | 0.4 | 0.7 | 1.2 | 1.8 | 20.3 |
| 1 | `products.get` | 1140.9 | 17114 | 0 | 0.4 | 0.3 | 0.7 | 1.2 | 1.8 | 4.2 |
| 8 | `products.list` | 3862.1 | 57937 | 0 | 1.0 | 0.8 | 2.0 | 2.5 | 3.3 | 7.6 |
| 8 | `products.get` | 3861.7 | 57932 | 0 | 1.0 | 0.8 | 2.0 | 2.4 | 3.3 | 6.2 |
| 32 | `products.list` | 6544.8 | 98190 | 0 | 2.5 | 2.2 | 4.0 | 4.7 | 6.3 | 18.3 |
| 32 | `products.get` | 6543.6 | 98173 | 0 | 2.4 | 2.2 | 4.0 | 4.7 | 6.3 | 24.1 |
| 64 | `products.list` | 7454.0 | 111836 | 0 | 4.3 | 3.9 | 6.8 | 8.1 | 12.1 | 30.0 |
| 64 | `products.get` | 7451.8 | 111803 | 0 | 4.3 | 3.9 | 6.8 | 8.1 | 11.7 | 32.4 |

Measured by raygate (upstream time, from its `/metrics` histogram; percentiles are bucket bounds):

| VUs | route | admitted | mean ms | p50 | p95 | p99 | upstream errors | breaker fast-fail | 429 |
|---:|---|---:|---:|---|---|---|---:|---:|---:|
| 1 | products | 34228 | 0.3 | ≤ 5 | ≤ 5 | ≤ 5 | 0 | 0 | 0 |
| 8 | products | 115869 | 0.6 | ≤ 5 | ≤ 5 | ≤ 5 | 0 | 0 | 0 |
| 32 | products | 196363 | 1.5 | ≤ 5 | ≤ 5 | ≤ 5 | 0 | 0 | 0 |
| 64 | products | 223639 | 2.5 | ≤ 5 | ≤ 10 | ≤ 10 | 0 | 0 | 0 |

## browse-direct

the same reads straight to the products service: the gap to `browse` is the gateway's cost.

| VUs | step | ok/s | ok | errors | mean ms | p50 | p90 | p95 | p99 | max |
|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `products.list` | 2528.0 | 37922 | 0 | 0.2 | 0.2 | 0.2 | 0.3 | 1.0 | 3.5 |
| 1 | `products.get` | 2528.0 | 37922 | 0 | 0.2 | 0.2 | 0.2 | 0.3 | 1.0 | 3.4 |
| 8 | `products.list` | 9378.6 | 140708 | 0 | 0.4 | 0.3 | 0.8 | 1.2 | 2.2 | 5.7 |
| 8 | `products.get` | 9378.4 | 140704 | 0 | 0.4 | 0.3 | 0.8 | 1.2 | 2.2 | 8.2 |
| 32 | `products.list` | 14815.4 | 222315 | 0 | 1.1 | 0.9 | 2.1 | 2.6 | 3.6 | 8.6 |
| 32 | `products.get` | 14814.5 | 222301 | 0 | 1.1 | 0.9 | 2.1 | 2.6 | 3.6 | 9.6 |
| 64 | `products.list` | 13870.3 | 208123 | 0 | 2.3 | 1.9 | 4.6 | 5.7 | 8.2 | 19.9 |
| 64 | `products.get` | 13867.9 | 208088 | 0 | 2.3 | 1.9 | 4.6 | 5.6 | 8.1 | 26.7 |

## cart

add, read and remove a cart line through raygate (raykv + an rpc to products per add).

| VUs | step | ok/s | ok | errors | mean ms | p50 | p90 | p95 | p99 | max |
|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `cart.add` | 217.2 | 3260 | 0 | 2.5 | 2.3 | 3.9 | 4.6 | 5.8 | 8.3 |
| 1 | `cart.get` | 217.2 | 3260 | 0 | 0.7 | 0.4 | 1.4 | 1.8 | 2.9 | 4.8 |
| 1 | `cart.remove` | 217.2 | 3260 | 0 | 1.4 | 1.2 | 2.5 | 2.9 | 4.1 | 8.6 |
| 8 | `cart.add` | 589.2 | 8843 | 0 | 6.0 | 5.6 | 9.2 | 10.8 | 13.6 | 25.6 |
| 8 | `cart.get` | 589.2 | 8843 | 0 | 2.7 | 2.4 | 4.8 | 5.8 | 7.9 | 19.5 |
| 8 | `cart.remove` | 589.2 | 8843 | 0 | 4.8 | 4.4 | 7.7 | 9.0 | 12.2 | 27.6 |
| 32 | `cart.add` | 764.4 | 11479 | 0 | 17.2 | 16.5 | 25.7 | 28.8 | 35.0 | 53.9 |
| 32 | `cart.get` | 764.4 | 11479 | 0 | 8.4 | 7.7 | 14.6 | 16.8 | 21.7 | 42.3 |
| 32 | `cart.remove` | 764.4 | 11479 | 0 | 16.3 | 15.6 | 24.6 | 27.7 | 33.8 | 55.6 |
| 64 | `cart.add` | 679.0 | 10212 | 0 | 38.9 | 30.8 | 49.5 | 56.4 | 71.3 | 2648.0 |
| 64 | `cart.get` | 679.0 | 10212 | 0 | 19.5 | 14.6 | 28.5 | 33.7 | 45.2 | 2622.1 |
| 64 | `cart.remove` | 679.0 | 10212 | 0 | 35.7 | 29.0 | 47.2 | 53.2 | 68.3 | 2637.7 |

Measured by raygate (upstream time, from its `/metrics` histogram; percentiles are bucket bounds):

| VUs | route | admitted | mean ms | p50 | p95 | p99 | upstream errors | breaker fast-fail | 429 |
|---:|---|---:|---:|---|---|---|---:|---:|---:|
| 1 | cart | 9780 | 1.2 | ≤ 5 | ≤ 5 | ≤ 5 | 0 | 0 | 0 |
| 8 | cart | 26529 | 4.1 | ≤ 5 | ≤ 10 | ≤ 25 | 0 | 0 | 0 |
| 32 | cart | 34437 | 13.4 | ≤ 25 | ≤ 50 | ≤ 50 | 0 | 0 | 0 |
| 64 | cart | 30636 | 30.7 | ≤ 25 | ≤ 100 | ≤ 100 | 0 | 0 | 0 |

## purchase

add to cart → checkout → poll the order until the saga settles it (outbox → gRPC → rayq → worker → rayq → consumer).

| VUs | step | ok/s | ok | errors | mean ms | p50 | p90 | p95 | p99 | max |
|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `cart.add` | 4.4 | 66 | 0 | 2.3 | 2.1 | 3.4 | 3.9 | 6.8 | 6.8 |
| 1 | `orders.place` | 4.4 | 66 | 0 | 3.6 | 3.4 | 4.8 | 5.2 | 7.9 | 7.9 |
| 1 | `orders.get` | 9.2 | 139 | 0 | 0.9 | 0.8 | 1.2 | 1.6 | 2.6 | 3.4 |
| 1 | `purchase.to_paid` | 4.0 | 60 | 0 | 228.9 | 205.3 | 405.8 | 406.7 | 409.8 | 409.8 |
| 1 | `purchase.to_cancelled` | 0.4 | 6 | 0 | 205.3 | 204.4 | 207.4 | 207.4 | 207.4 | 207.4 |
| 8 | `cart.add` | 36.9 | 559 | 0 | 2.4 | 2.1 | 3.6 | 4.4 | 8.6 | 13.4 |
| 8 | `orders.place` | 36.9 | 559 | 0 | 4.6 | 4.0 | 7.3 | 8.9 | 11.7 | 14.1 |
| 8 | `orders.get` | 75.0 | 1137 | 0 | 0.9 | 0.7 | 1.7 | 2.1 | 3.4 | 4.2 |
| 8 | `purchase.to_paid` | 33.2 | 503 | 0 | 213.9 | 206.0 | 210.8 | 213.6 | 409.5 | 413.1 |
| 8 | `purchase.to_cancelled` | 3.7 | 56 | 0 | 210.0 | 205.8 | 209.2 | 213.3 | 407.9 | 407.9 |
| 32 | `cart.add` | 99.1 | 1519 | 0 | 5.7 | 4.2 | 10.7 | 13.7 | 29.7 | 42.6 |
| 32 | `orders.place` | 99.1 | 1519 | 0 | 11.5 | 9.9 | 20.2 | 25.6 | 40.8 | 65.4 |
| 32 | `orders.get` | 246.0 | 3769 | 0 | 1.8 | 1.4 | 3.4 | 4.3 | 7.1 | 15.4 |
| 32 | `purchase.to_paid` | 89.3 | 1368 | 0 | 313.1 | 232.2 | 423.1 | 430.5 | 450.6 | 469.9 |
| 32 | `purchase.to_cancelled` | 9.9 | 151 | 0 | 308.2 | 223.4 | 420.1 | 430.5 | 441.6 | 446.9 |
| 64 | `cart.add` | 145.8 | 2247 | 0 | 7.9 | 5.4 | 12.4 | 19.5 | 52.7 | 106.7 |
| 64 | `orders.place` | 145.8 | 2247 | 0 | 15.5 | 12.9 | 25.6 | 33.4 | 61.9 | 87.2 |
| 64 | `orders.get` | 438.8 | 6765 | 0 | 2.4 | 2.0 | 4.5 | 5.7 | 8.5 | 14.9 |
| 64 | `purchase.to_paid` | 131.3 | 2024 | 0 | 424.3 | 420.5 | 446.8 | 617.8 | 628.3 | 651.5 |
| 64 | `purchase.to_cancelled` | 14.5 | 223 | 0 | 435.3 | 421.5 | 619.4 | 625.2 | 632.2 | 654.2 |

Measured by raygate (upstream time, from its `/metrics` histogram; percentiles are bucket bounds):

| VUs | route | admitted | mean ms | p50 | p95 | p99 | upstream errors | breaker fast-fail | 429 |
|---:|---|---:|---:|---|---|---|---:|---:|---:|
| 1 | cart | 66 | 2.1 | ≤ 5 | ≤ 5 | ≤ 10 | 0 | 0 | 0 |
| 1 | orders | 205 | 1.5 | ≤ 5 | ≤ 5 | ≤ 5 | 0 | 0 | 0 |
| 8 | cart | 559 | 2.1 | ≤ 5 | ≤ 5 | ≤ 10 | 0 | 0 | 0 |
| 8 | orders | 1696 | 1.9 | ≤ 5 | ≤ 10 | ≤ 10 | 0 | 0 | 0 |
| 32 | cart | 1519 | 5.2 | ≤ 5 | ≤ 25 | ≤ 50 | 0 | 0 | 0 |
| 32 | orders | 5288 | 4.1 | ≤ 5 | ≤ 25 | ≤ 50 | 0 | 0 | 0 |
| 64 | cart | 2247 | 7.2 | ≤ 5 | ≤ 25 | ≤ 100 | 0 | 0 | 0 |
| 64 | orders | 9012 | 5.0 | ≤ 5 | ≤ 25 | ≤ 50 | 0 | 0 | 0 |

Outcomes (every 10th card is declined, so the compensation runs too):

| VUs | purchases/s | paid | cancelled | timeout | checkout failed | peak backlog payment.jobs / payment.results | stock of product 5 |
|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | 4.4 | 60 | 6 | 0 | 0 | 1 / 1 | 200 → 140 (expected 140) |
| 8 | 36.9 | 503 | 56 | 0 | 0 | 8 / 8 | 1200 → 697 (expected 697) |
| 32 | 99.1 | 1368 | 151 | 0 | 0 | 15 / 25 | 4800 → 3432 (expected 3432) |
| 64 | 145.8 | 2024 | 223 | 0 | 0 | 34 / 31 | 9600 → 7576 (expected 7576) |

- ✓ purchase × 1: stock conserved — 200 − 60 units paid = 140
- ✓ purchase × 1: every order settled within 60 s (0 did not)
- ✓ purchase × 8: stock conserved — 1200 − 503 units paid = 697
- ✓ purchase × 8: every order settled within 60 s (0 did not)
- ✓ purchase × 32: stock conserved — 4800 − 1368 units paid = 3432
- ✓ purchase × 32: every order settled within 60 s (0 did not)
- ✓ purchase × 64: stock conserved — 9600 − 2024 units paid = 7576
- ✓ purchase × 64: every order settled within 60 s (0 did not)

## drain

every VU buys one unit of the same product until it sells out: exactly the stock must be sold.

| VUs | step | ok/s | ok | errors | mean ms | p50 | p90 | p95 | p99 | max |
|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 64 | `cart.add` | 156.9 | 564 | 0 | 13.7 | 6.6 | 34.6 | 52.4 | 115.0 | 122.1 |
| 64 | `orders.place` | 139.6 | 502 | 0 | 23.7 | 17.2 | 55.7 | 71.8 | 97.1 | 129.0 |
| 64 | `orders.get` | 404.1 | 1453 | 0 | 2.8 | 2.1 | 5.5 | 7.7 | 13.6 | 19.0 |
| 64 | `purchase.to_paid` | 139.1 | 500 | 0 | 413.6 | 422.2 | 452.3 | 478.2 | 643.5 | 669.0 |
| 64 | `cart.clear` | 0.6 | 2 | 0 | 2.5 | 2.0 | 3.0 | 3.0 | 3.0 | 3.0 |

Measured by raygate (upstream time, from its `/metrics` histogram; percentiles are bucket bounds):

| VUs | route | admitted | mean ms | p50 | p95 | p99 | upstream errors | breaker fast-fail | 429 |
|---:|---|---:|---:|---|---|---|---:|---:|---:|
| 64 | cart | 566 | 12.6 | ≤ 10 | ≤ 50 | ≤ 250 | 0 | 0 | 0 |
| 64 | orders | 1955 | 7.4 | ≤ 5 | ≤ 50 | ≤ 100 | 0 | 0 | 0 |

64 VUs raced for 500 units of product 4 (peak backlog: payment.jobs 13, payment.results 30):

- ✓ exactly the stock was sold: 500 units accepted for 500 in stock (never one more)
- ✓ every accepted order was paid (500 of 500)
- ✓ the product ends at 0 units (0)
- ✓ every VU was told it sold out (409) — 64 of 64

(Stock restored to 0.)

## Resources

Host: Apple M3 Pro, 11 cores · Docker: 6 CPUs, 15.6 GiB of memory, 29.6.1

CPU is % of one core (docker stats; sampled about every 2 s on the host). The five busiest containers per stage:

| stage | VUs | busiest containers — avg CPU % (peak) · peak memory |
|---|---:|---|
| browse | 1 | raygate 116.7 (137.0) · 27.8 MiB — products 102.5 (120.7) · 36.2 MiB — postgres 11.7 (14.1) · 61.2 MiB — rayq 10.1 (11.2) · 34.3 MiB — payment 9.9 (11.8) · 19.7 MiB |
| browse | 8 | raygate 142.7 (167.8) · 28.3 MiB — products 119.9 (139.1) · 36.5 MiB — postgres 42.0 (49.3) · 61.2 MiB — bench-run-65015d4d8972 28.2 (33.0) · 47.9 MiB — rayq 9.6 (11.3) · 34.2 MiB |
| browse | 32 | raygate 148.4 (165.7) · 29.1 MiB — products 122.6 (136.7) · 36.3 MiB — postgres 69.4 (77.2) · 61.2 MiB — bench-run-65015d4d8972 41.7 (46.9) · 50.5 MiB — rayq 9.3 (10.7) · 34.2 MiB |
| browse | 64 | raygate 138.5 (164.8) · 31.8 MiB — products 119.7 (142.1) · 36.6 MiB — postgres 72.5 (86.3) · 61.2 MiB — bench-run-65015d4d8972 42.7 (51.5) · 41.4 MiB — mongo 8.8 (23.8) · 342.7 MiB |
| browse-direct | 1 | products 150.9 (155.5) · 35.6 MiB — postgres 28.0 (56.5) · 61.2 MiB — bench-run-65015d4d8972 23.6 (36.7) · 43.3 MiB — rayq 11.1 (13.0) · 34.1 MiB — payment 10.3 (11.5) · 19.7 MiB |
| browse-direct | 8 | products 215.9 (233.8) · 35.6 MiB — postgres 96.2 (114.2) · 61.2 MiB — bench-run-65015d4d8972 62.8 (66.3) · 53.9 MiB — payment 9.9 (10.5) · 20.4 MiB — rayq 9.5 (10.4) · 34.1 MiB |
| browse-direct | 32 | products 222.1 (234.8) · 38.9 MiB — postgres 140.7 (149.7) · 61.5 MiB — bench-run-65015d4d8972 81.4 (87.1) · 59.4 MiB — payment 8.9 (10.2) · 20.0 MiB — rayq 8.7 (10.0) · 34.1 MiB |
| browse-direct | 64 | products 229.6 (237.7) · 38.4 MiB — postgres 139.4 (146.9) · 61.3 MiB — bench-run-65015d4d8972 79.8 (83.8) · 66.5 MiB — rayq 8.9 (9.3) · 34.1 MiB — payment 8.6 (9.2) · 19.7 MiB |
| cart | 1 | cart 93.3 (101.4) · 29.9 MiB — raygate 89.8 (106.0) · 30.9 MiB — raykv 74.4 (79.3) · 19.3 MiB — products 20.9 (35.3) · 37.6 MiB — payment 10.7 (11.2) · 20.5 MiB |
| cart | 8 | cart 101.9 (109.7) · 30.4 MiB — raygate 93.8 (101.6) · 31.3 MiB — raykv 84.6 (94.4) · 19.4 MiB — products 45.8 (49.6) · 37.3 MiB — mongo 9.7 (25.8) · 345.1 MiB |
| cart | 32 | cart 95.6 (104.7) · 29.9 MiB — raygate 85.9 (92.5) · 31.9 MiB — raykv 66.4 (73.0) · 19.4 MiB — products 47.3 (51.0) · 37.7 MiB — bench-run-65015d4d8972 10.5 (11.4) · 29.9 MiB |
| cart | 64 | cart 60.0 (94.8) · 31.9 MiB — raygate 54.5 (82.8) · 32.3 MiB — raykv 36.9 (56.6) · 19.4 MiB — products 31.8 (47.4) · 37.1 MiB — rayq 9.1 (10.1) · 34.1 MiB |
| purchase | 1 | rayq 11.4 (19.1) · 34.5 MiB — payment 11.2 (18.9) · 20.9 MiB — raygate 10.4 (17.9) · 31.7 MiB — cart 9.6 (16.2) · 31.2 MiB — mongo 9.0 (23.5) · 183.0 MiB |
| purchase | 8 | raygate 26.1 (37.4) · 31.8 MiB — rayq 24.4 (38.1) · 35.2 MiB — payment 20.9 (32.4) · 20.1 MiB — orders 20.8 (30.7) · 40.4 MiB — cart 19.2 (24.2) · 31.2 MiB |
| purchase | 32 | raygate 53.8 (62.6) · 32.2 MiB — orders 50.4 (61.9) · 44.6 MiB — rayq 44.2 (49.4) · 37.7 MiB — payment 35.0 (38.9) · 19.9 MiB — cart 34.5 (39.6) · 31.3 MiB |
| purchase | 64 | orders 51.9 (68.1) · 47.1 MiB — raygate 49.2 (66.2) · 32.7 MiB — rayq 47.8 (59.7) · 40.7 MiB — cart 38.6 (44.4) · 31.4 MiB — payment 38.1 (49.4) · 20.1 MiB |
| drain | 64 | orders 36.5 (36.5) · 46.9 MiB — rayq 31.5 (31.5) · 40.6 MiB — raygate 27.1 (27.1) · 31.7 MiB — mongo 27.0 (27.0) · 187.2 MiB — payment 24.3 (24.3) · 19.9 MiB |
