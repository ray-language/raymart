# raymart — benchmark

Started 2026-09-26T14:04:16Z · stages of 1 → 8 → 32 → 64 virtual users × 15 s · closed model (each VU waits for its answer) · keep-alive connections · load generator: native raylang, inside the compose network.

## Overview

| scenario | VUs | throughput and latency |
|---|---:|---|
| browse | 1 | 2102.9 ok/s · worst p99 1.9 ms · no errors |
| browse | 8 | 8097.7 ok/s · worst p99 3.1 ms · no errors |
| browse | 32 | 14993.1 ok/s · worst p99 5.8 ms · no errors |
| browse | 64 | 16885.2 ok/s · worst p99 11.3 ms · no errors |
| browse-direct | 1 | 5116.4 ok/s · worst p99 1.0 ms · no errors |
| browse-direct | 8 | 18219.4 ok/s · worst p99 2.3 ms · no errors |
| browse-direct | 32 | 28889.4 ok/s · worst p99 3.8 ms · no errors |
| browse-direct | 64 | 27418.9 ok/s · worst p99 8.2 ms · no errors |
| cart | 1 | 669.3 ok/s · worst p99 6.0 ms · no errors |
| cart | 8 | 1868.3 ok/s · worst p99 11.3 ms · no errors |
| cart | 32 | 2159.8 ok/s · worst p99 38.3 ms · no errors |
| cart | 64 | 2411.1 ok/s · worst p99 71.3 ms · no errors |
| purchase | 1 | 4.8 purchases/s · to paid p50 205.3 ms, p99 219.9 ms |
| purchase | 8 | 34.3 purchases/s · to paid p50 206.9 ms, p99 413.9 ms |
| purchase | 32 | 100.2 purchases/s · to paid p50 231.1 ms, p99 434.7 ms |
| purchase | 64 | 138.8 purchases/s · to paid p50 427.6 ms, p99 652.8 ms |
| drain | 64 | 500 units sold out in 3.6 s (137.8 orders/s) |

Invariants: all held ✓

## browse

`GET /api/products` and `GET /api/products/:id` through raygate (PostgreSQL reads).

| VUs | step | ok/s | ok | errors | mean ms | p50 | p90 | p95 | p99 | max |
|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `products.list` | 1051.5 | 15774 | 0 | 0.5 | 0.4 | 0.9 | 1.2 | 1.9 | 17.4 |
| 1 | `products.get` | 1051.4 | 15773 | 0 | 0.5 | 0.4 | 0.9 | 1.2 | 1.9 | 5.4 |
| 8 | `products.list` | 4049.0 | 60741 | 0 | 1.0 | 0.8 | 1.9 | 2.3 | 3.1 | 7.5 |
| 8 | `products.get` | 4048.6 | 60735 | 0 | 1.0 | 0.7 | 1.9 | 2.3 | 3.1 | 8.1 |
| 32 | `products.list` | 7497.1 | 112485 | 0 | 2.1 | 1.9 | 3.5 | 4.2 | 5.8 | 22.8 |
| 32 | `products.get` | 7496.0 | 112469 | 0 | 2.1 | 1.9 | 3.5 | 4.1 | 5.8 | 16.7 |
| 64 | `products.list` | 8443.8 | 126718 | 0 | 3.8 | 3.4 | 6.2 | 7.5 | 11.3 | 34.4 |
| 64 | `products.get` | 8441.5 | 126684 | 0 | 3.8 | 3.3 | 6.1 | 7.4 | 11.3 | 34.4 |

Measured by raygate (upstream time, from its `/metrics` histogram; percentiles are bucket bounds):

| VUs | route | admitted | mean ms | p50 | p95 | p99 | upstream errors | breaker fast-fail | 429 |
|---:|---|---:|---:|---|---|---|---:|---:|---:|
| 1 | products | 31547 | 0.3 | ≤ 5 | ≤ 5 | ≤ 5 | 0 | 0 | 0 |
| 8 | products | 121476 | 0.6 | ≤ 5 | ≤ 5 | ≤ 5 | 0 | 0 | 0 |
| 32 | products | 224954 | 1.3 | ≤ 5 | ≤ 5 | ≤ 5 | 0 | 0 | 0 |
| 64 | products | 253402 | 2.3 | ≤ 5 | ≤ 10 | ≤ 10 | 0 | 0 | 0 |

## browse-direct

the same reads straight to the products service: the gap to `browse` is the gateway's cost.

| VUs | step | ok/s | ok | errors | mean ms | p50 | p90 | p95 | p99 | max |
|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `products.list` | 2558.2 | 38376 | 0 | 0.2 | 0.2 | 0.2 | 0.3 | 1.0 | 5.5 |
| 1 | `products.get` | 2558.2 | 38375 | 0 | 0.2 | 0.2 | 0.2 | 0.2 | 1.0 | 4.6 |
| 8 | `products.list` | 9109.8 | 136668 | 0 | 0.5 | 0.3 | 0.9 | 1.3 | 2.3 | 6.6 |
| 8 | `products.get` | 9109.6 | 136666 | 0 | 0.4 | 0.3 | 0.8 | 1.2 | 2.3 | 6.1 |
| 32 | `products.list` | 14445.3 | 216766 | 0 | 1.1 | 0.9 | 2.1 | 2.7 | 3.8 | 15.9 |
| 32 | `products.get` | 14444.1 | 216748 | 0 | 1.1 | 0.9 | 2.1 | 2.6 | 3.8 | 15.8 |
| 64 | `products.list` | 13710.5 | 205726 | 0 | 2.3 | 1.9 | 4.6 | 5.7 | 8.2 | 27.5 |
| 64 | `products.get` | 13708.4 | 205694 | 0 | 2.3 | 1.9 | 4.6 | 5.6 | 8.2 | 24.8 |

## cart

add, read and remove a cart line through raygate (raykv + an rpc to products per add).

| VUs | step | ok/s | ok | errors | mean ms | p50 | p90 | p95 | p99 | max |
|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `cart.add` | 223.1 | 3347 | 0 | 2.4 | 2.1 | 3.8 | 4.4 | 6.0 | 28.1 |
| 1 | `cart.get` | 223.1 | 3347 | 0 | 0.7 | 0.5 | 1.5 | 2.1 | 2.9 | 4.0 |
| 1 | `cart.remove` | 223.1 | 3347 | 0 | 1.4 | 1.1 | 2.4 | 2.9 | 4.0 | 8.3 |
| 8 | `cart.add` | 622.8 | 9349 | 0 | 5.8 | 5.5 | 8.3 | 9.3 | 11.3 | 32.8 |
| 8 | `cart.get` | 622.8 | 9349 | 0 | 2.5 | 2.3 | 4.4 | 5.1 | 6.8 | 17.8 |
| 8 | `cart.remove` | 622.8 | 9349 | 0 | 4.5 | 4.3 | 6.9 | 7.8 | 9.8 | 30.9 |
| 32 | `cart.add` | 719.9 | 10814 | 0 | 18.1 | 17.5 | 27.1 | 30.8 | 38.3 | 57.3 |
| 32 | `cart.get` | 719.9 | 10814 | 0 | 8.9 | 8.0 | 15.2 | 17.8 | 23.5 | 44.8 |
| 32 | `cart.remove` | 719.9 | 10814 | 0 | 17.4 | 16.6 | 26.5 | 30.0 | 38.3 | 67.9 |
| 64 | `cart.add` | 803.7 | 12091 | 0 | 32.8 | 31.0 | 49.3 | 55.9 | 71.3 | 297.6 |
| 64 | `cart.get` | 803.7 | 12091 | 0 | 16.1 | 14.5 | 28.2 | 33.1 | 44.2 | 265.6 |
| 64 | `cart.remove` | 803.7 | 12091 | 0 | 30.7 | 28.9 | 47.1 | 54.3 | 68.7 | 301.2 |

Measured by raygate (upstream time, from its `/metrics` histogram; percentiles are bucket bounds):

| VUs | route | admitted | mean ms | p50 | p95 | p99 | upstream errors | breaker fast-fail | 429 |
|---:|---|---:|---:|---|---|---|---:|---:|---:|
| 1 | cart | 10041 | 1.2 | ≤ 5 | ≤ 5 | ≤ 5 | 0 | 0 | 0 |
| 8 | cart | 28047 | 3.9 | ≤ 5 | ≤ 10 | ≤ 10 | 0 | 0 | 0 |
| 32 | cart | 32442 | 14.2 | ≤ 25 | ≤ 50 | ≤ 50 | 0 | 0 | 0 |
| 64 | cart | 36273 | 25.8 | ≤ 25 | ≤ 100 | ≤ 100 | 0 | 0 | 0 |

## purchase

add to cart → checkout → poll the order until the saga settles it (outbox → gRPC → rayq → worker → rayq → consumer).

| VUs | step | ok/s | ok | errors | mean ms | p50 | p90 | p95 | p99 | max |
|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `cart.add` | 4.8 | 72 | 0 | 2.5 | 2.2 | 3.1 | 4.8 | 8.6 | 8.6 |
| 1 | `orders.place` | 4.8 | 72 | 0 | 4.0 | 3.5 | 4.7 | 7.1 | 17.5 | 17.5 |
| 1 | `orders.get` | 9.6 | 144 | 0 | 0.9 | 0.8 | 1.2 | 1.5 | 2.7 | 3.4 |
| 1 | `purchase.to_paid` | 4.3 | 65 | 0 | 205.9 | 205.3 | 206.8 | 211.0 | 219.9 | 219.9 |
| 1 | `purchase.to_cancelled` | 0.5 | 7 | 0 | 205.6 | 205.6 | 207.6 | 207.6 | 207.6 | 207.6 |
| 8 | `cart.add` | 34.3 | 519 | 0 | 2.6 | 2.1 | 4.6 | 5.1 | 8.4 | 18.5 |
| 8 | `orders.place` | 34.3 | 519 | 0 | 5.5 | 4.5 | 9.1 | 10.8 | 15.6 | 29.1 |
| 8 | `orders.get` | 72.5 | 1095 | 0 | 1.0 | 0.8 | 1.9 | 2.4 | 3.8 | 7.5 |
| 8 | `purchase.to_paid` | 31.0 | 469 | 0 | 229.1 | 206.9 | 405.9 | 410.3 | 413.9 | 416.8 |
| 8 | `purchase.to_cancelled` | 3.3 | 50 | 0 | 236.3 | 207.4 | 406.3 | 407.7 | 411.3 | 411.3 |
| 32 | `cart.add` | 100.2 | 1524 | 0 | 5.6 | 4.1 | 10.0 | 13.9 | 32.8 | 39.2 |
| 32 | `orders.place` | 100.2 | 1524 | 0 | 11.1 | 9.7 | 19.4 | 23.8 | 32.9 | 51.5 |
| 32 | `orders.get` | 248.0 | 3771 | 0 | 1.9 | 1.5 | 3.5 | 4.4 | 6.9 | 16.1 |
| 32 | `purchase.to_paid` | 90.3 | 1373 | 0 | 311.7 | 231.1 | 420.5 | 426.9 | 434.7 | 449.4 |
| 32 | `purchase.to_cancelled` | 9.9 | 151 | 0 | 304.9 | 226.3 | 420.4 | 424.7 | 432.6 | 433.8 |
| 64 | `cart.add` | 138.8 | 2140 | 0 | 9.8 | 7.0 | 17.5 | 25.7 | 52.4 | 112.7 |
| 64 | `orders.place` | 138.8 | 2140 | 0 | 19.8 | 16.6 | 33.1 | 40.8 | 67.9 | 152.9 |
| 64 | `orders.get` | 428.0 | 6598 | 0 | 3.1 | 2.4 | 5.8 | 7.3 | 11.4 | 44.5 |
| 64 | `purchase.to_paid` | 124.8 | 1923 | 0 | 446.1 | 427.6 | 623.9 | 638.7 | 652.8 | 780.3 |
| 64 | `purchase.to_cancelled` | 14.1 | 217 | 0 | 448.8 | 426.6 | 626.5 | 641.2 | 658.0 | 759.5 |

Measured by raygate (upstream time, from its `/metrics` histogram; percentiles are bucket bounds):

| VUs | route | admitted | mean ms | p50 | p95 | p99 | upstream errors | breaker fast-fail | 429 |
|---:|---|---:|---:|---|---|---|---:|---:|---:|
| 1 | cart | 72 | 2.2 | ≤ 5 | ≤ 5 | ≤ 10 | 0 | 0 | 0 |
| 1 | orders | 216 | 1.7 | ≤ 5 | ≤ 5 | ≤ 10 | 0 | 0 | 0 |
| 8 | cart | 519 | 2.3 | ≤ 5 | ≤ 5 | ≤ 10 | 0 | 0 | 0 |
| 8 | orders | 1614 | 2.2 | ≤ 5 | ≤ 10 | ≤ 25 | 0 | 0 | 0 |
| 32 | cart | 1524 | 5.1 | ≤ 5 | ≤ 25 | ≤ 50 | 0 | 0 | 0 |
| 32 | orders | 5295 | 4.0 | ≤ 5 | ≤ 25 | ≤ 25 | 0 | 0 | 0 |
| 64 | cart | 2140 | 8.9 | ≤ 10 | ≤ 25 | ≤ 50 | 0 | 0 | 0 |
| 64 | orders | 8738 | 6.4 | ≤ 5 | ≤ 25 | ≤ 50 | 0 | 0 | 0 |

Outcomes (every 10th card is declined, so the compensation runs too):

| VUs | purchases/s | paid | cancelled | timeout | checkout failed | peak backlog payment.jobs / payment.results | stock of product 5 |
|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | 4.8 | 65 | 7 | 0 | 0 | 1 / 1 | 200 → 135 (expected 135) |
| 8 | 34.3 | 469 | 50 | 0 | 0 | 8 / 8 | 1200 → 731 (expected 731) |
| 32 | 100.2 | 1373 | 151 | 0 | 0 | 25 / 24 | 4800 → 3427 (expected 3427) |
| 64 | 138.8 | 1923 | 217 | 0 | 0 | 24 / 35 | 9600 → 7677 (expected 7677) |

- ✓ purchase × 1: stock conserved — 200 − 65 units paid = 135
- ✓ purchase × 1: every order settled within 60 s (0 did not)
- ✓ purchase × 8: stock conserved — 1200 − 469 units paid = 731
- ✓ purchase × 8: every order settled within 60 s (0 did not)
- ✓ purchase × 32: stock conserved — 4800 − 1373 units paid = 3427
- ✓ purchase × 32: every order settled within 60 s (0 did not)
- ✓ purchase × 64: stock conserved — 9600 − 1923 units paid = 7677
- ✓ purchase × 64: every order settled within 60 s (0 did not)

## drain

every VU buys one unit of the same product until it sells out: exactly the stock must be sold.

| VUs | step | ok/s | ok | errors | mean ms | p50 | p90 | p95 | p99 | max |
|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 64 | `cart.add` | 155.5 | 564 | 0 | 12.2 | 6.8 | 33.0 | 47.1 | 81.2 | 83.8 |
| 64 | `orders.place` | 138.7 | 503 | 0 | 24.2 | 16.2 | 58.5 | 75.6 | 94.3 | 122.2 |
| 64 | `orders.get` | 401.1 | 1455 | 0 | 2.8 | 2.2 | 5.5 | 6.8 | 10.2 | 17.5 |
| 64 | `purchase.to_paid` | 137.8 | 500 | 0 | 414.8 | 422.7 | 453.4 | 482.8 | 516.0 | 619.0 |
| 64 | `cart.clear` | 0.8 | 3 | 0 | 2.1 | 2.4 | 2.5 | 2.5 | 2.5 | 2.5 |

Measured by raygate (upstream time, from its `/metrics` histogram; percentiles are bucket bounds):

| VUs | route | admitted | mean ms | p50 | p95 | p99 | upstream errors | breaker fast-fail | 429 |
|---:|---|---:|---:|---|---|---|---:|---:|---:|
| 64 | cart | 567 | 11.3 | ≤ 10 | ≤ 50 | ≤ 100 | 0 | 0 | 0 |
| 64 | orders | 1958 | 7.5 | ≤ 5 | ≤ 50 | ≤ 100 | 0 | 0 | 0 |

64 VUs raced for 500 units of product 4 (peak backlog: payment.jobs 20, payment.results 11):

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
| browse | 1 | raygate 119.6 (140.2) · 29.8 MiB — products 102.0 (120.6) · 36.4 MiB — postgres 12.7 (16.3) · 52.3 MiB — rayq 10.3 (11.5) · 17.6 MiB — payment 10.3 (11.5) · 22.4 MiB |
| browse | 8 | raygate 154.6 (177.9) · 34.7 MiB — products 127.2 (146.6) · 36.4 MiB — postgres 46.8 (55.3) · 53.3 MiB — bench-run-9a7092e44f12 31.3 (36.1) · 51.4 MiB — rayq 9.2 (9.9) · 17.4 MiB |
| browse | 32 | raygate 153.1 (175.1) · 38.7 MiB — products 132.1 (147.2) · 36.1 MiB — postgres 79.1 (89.8) · 53.3 MiB — bench-run-9a7092e44f12 48.5 (55.8) · 54.8 MiB — mongo 9.2 (24.1) · 301.3 MiB |
| browse | 64 | raygate 148.0 (177.5) · 39.4 MiB — products 132.5 (162.5) · 36.1 MiB — postgres 81.6 (100.1) · 53.3 MiB — bench-run-9a7092e44f12 48.7 (60.8) · 48.3 MiB — rayq 8.0 (8.5) · 17.4 MiB |
| browse-direct | 1 | products 146.8 (149.2) · 35.3 MiB — postgres 30.3 (60.9) · 53.3 MiB — bench-run-9a7092e44f12 25.2 (41.2) · 49.3 MiB — rayq 10.8 (12.1) · 17.7 MiB — payment 10.1 (11.1) · 22.6 MiB |
| browse-direct | 8 | products 222.0 (236.3) · 35.6 MiB — postgres 96.8 (114.5) · 53.6 MiB — bench-run-9a7092e44f12 61.4 (64.0) · 53.0 MiB — rayq 10.0 (11.0) · 17.5 MiB — payment 9.5 (10.9) · 22.3 MiB |
| browse-direct | 32 | products 228.5 (239.1) · 35.9 MiB — postgres 143.2 (151.1) · 53.3 MiB — bench-run-9a7092e44f12 82.0 (86.9) · 63.5 MiB — rayq 9.3 (10.4) · 17.5 MiB — payment 9.0 (10.3) · 22.3 MiB |
| browse-direct | 64 | products 202.0 (240.6) · 36.7 MiB — postgres 121.1 (144.6) · 53.3 MiB — bench-run-9a7092e44f12 69.2 (82.1) · 70.0 MiB — rayq 9.2 (11.7) · 17.7 MiB — payment 9.0 (9.8) · 22.3 MiB |
| cart | 1 | cart 96.3 (108.7) · 30.3 MiB — raygate 82.4 (109.4) · 38.4 MiB — raykv 81.1 (91.5) · 18.3 MiB — products 24.0 (47.1) · 35.1 MiB — payment 11.0 (12.3) · 22.3 MiB |
| cart | 8 | cart 102.6 (111.1) · 30.7 MiB — raygate 97.6 (106.3) · 37.9 MiB — raykv 83.4 (94.1) · 18.4 MiB — products 45.9 (50.5) · 35.1 MiB — rayq 9.7 (10.8) · 17.5 MiB |
| cart | 32 | cart 91.9 (105.8) · 30.6 MiB — raygate 84.8 (95.9) · 38.5 MiB — raykv 64.1 (71.3) · 18.3 MiB — products 46.2 (50.5) · 35.0 MiB — bench-run-9a7092e44f12 10.3 (11.5) · 35.3 MiB |
| cart | 64 | cart 75.7 (98.3) · 30.6 MiB — raygate 69.7 (86.1) · 39.2 MiB — raykv 45.3 (57.1) · 20.6 MiB — products 39.7 (50.1) · 35.2 MiB — rayq 9.6 (11.0) · 17.7 MiB |
| purchase | 1 | rayq 12.9 (23.0) · 19.7 MiB — payment 11.2 (20.5) · 22.4 MiB — raygate 11.1 (19.4) · 38.3 MiB — cart 10.0 (17.6) · 29.7 MiB — products 9.6 (17.6) · 35.5 MiB |
| purchase | 8 | raygate 23.3 (25.7) · 38.4 MiB — rayq 20.8 (25.2) · 20.0 MiB — orders 18.2 (21.3) · 44.6 MiB — payment 17.7 (21.0) · 22.4 MiB — cart 17.1 (20.4) · 29.9 MiB |
| purchase | 32 | raygate 55.6 (62.3) · 38.4 MiB — orders 50.4 (58.6) · 44.8 MiB — rayq 44.3 (51.2) · 22.9 MiB — cart 34.4 (37.3) · 29.6 MiB — payment 33.3 (37.8) · 22.7 MiB |
| purchase | 64 | rayq 49.4 (61.0) · 25.8 MiB — orders 49.1 (65.4) · 45.1 MiB — raygate 48.7 (63.9) · 39.1 MiB — payment 38.6 (44.7) · 22.5 MiB — cart 35.0 (44.1) · 29.9 MiB |
| drain | 64 | raygate 34.9 (56.6) · 40.8 MiB — orders 32.0 (35.4) · 47.1 MiB — rayq 31.0 (51.5) · 26.4 MiB — products 26.3 (42.1) · 35.0 MiB — cart 25.9 (41.4) · 29.9 MiB |
