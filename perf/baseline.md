# raymart — benchmark

Started 2026-09-26T07:02:03Z · stages of 1 → 8 → 32 → 64 virtual users × 15 s · closed model (each VU waits for its answer) · keep-alive connections · load generator: native raylang, inside the compose network.

## Overview

| scenario | VUs | throughput and latency |
|---|---:|---|
| browse | 1 | 244.4 ok/s · worst p99 6.8 ms · no errors |
| browse | 8 | 704.9 ok/s · worst p99 20.6 ms · no errors |
| browse | 32 | 761.4 ok/s · worst p99 72.5 ms · no errors |
| browse | 64 | 265.8 ok/s · worst p99 168.1 ms · **58.3 % errors** (5602) |
| browse-direct | 1 | 270.7 ok/s · worst p99 6.8 ms · no errors |
| browse-direct | 8 | 856.1 ok/s · worst p99 18.7 ms · no errors |
| browse-direct | 32 | 866.4 ok/s · worst p99 68.6 ms · no errors |
| browse-direct | 64 | 42.7 ok/s · worst p99 137.1 ms · **93.3 % errors** (8960) |
| cart | 1 | 301.3 ok/s · worst p99 13.4 ms · no errors |
| cart | 8 | 694.1 ok/s · worst p99 41.5 ms · no errors |
| cart | 32 | 130.3 ok/s · worst p99 103.5 ms · **67.0 % errors** (4033) |
| cart | 64 | 1038.3 ok/s · worst p99 333.8 ms · no errors |
| purchase | 1 | 1.5 purchases/s · to paid p50 616.7 ms, p99 1032.6 ms |
| purchase | 8 | 9.1 purchases/s · to paid p50 828.3 ms, p99 1233.4 ms |
| purchase | 32 | 25.3 purchases/s · to paid p50 1231.8 ms, p99 1735.5 ms |
| purchase | 64 | 26.5 purchases/s · to paid p50 2277.0 ms, p99 2858.0 ms |
| drain | 64 | 500 units sold out in 24.5 s (20.4 orders/s) |

Invariants: all held ✓

## browse

`GET /api/products` and `GET /api/products/:id` through raygate (PostgreSQL reads).

| VUs | step | ok/s | ok | errors | mean ms | p50 | p90 | p95 | p99 | max |
|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `products.list` | 122.2 | 1834 | 0 | 4.1 | 3.9 | 5.0 | 5.6 | 6.8 | 8.9 |
| 1 | `products.get` | 122.2 | 1833 | 0 | 4.1 | 3.8 | 5.1 | 5.7 | 6.5 | 9.3 |
| 8 | `products.list` | 352.6 | 5293 | 0 | 11.4 | 11.1 | 15.5 | 17.0 | 20.4 | 31.0 |
| 8 | `products.get` | 352.3 | 5289 | 0 | 11.3 | 10.9 | 15.4 | 16.9 | 20.6 | 28.2 |
| 32 | `products.list` | 381.1 | 5733 | 0 | 42.1 | 41.4 | 56.3 | 61.9 | 72.5 | 95.9 |
| 32 | `products.get` | 380.3 | 5722 | 0 | 41.8 | 41.2 | 56.0 | 60.5 | 70.4 | 97.8 |
| 64 | `products.list` | 134.0 | 2023 | **2800** (503×2800) | 97.1 | 95.5 | 131.2 | 142.5 | 168.1 | 195.3 |
| 64 | `products.get` | 131.9 | 1991 | **2802** (503×2802) | 96.5 | 94.9 | 131.5 | 142.3 | 164.3 | 189.7 |

Measured by raygate (upstream time, from its `/metrics` histogram; percentiles are bucket bounds):

| VUs | route | admitted | mean ms | p50 | p95 | p99 | upstream errors | breaker fast-fail | 429 |
|---:|---|---:|---:|---|---|---|---:|---:|---:|
| 1 | products | 3667 | 3.8 | ≤ 5 | ≤ 5 | ≤ 10 | 0 | 0 | 0 |
| 8 | products | 10582 | 10.9 | ≤ 25 | ≤ 25 | ≤ 25 | 0 | 0 | 0 |
| 32 | products | 11455 | 41.3 | ≤ 50 | ≤ 100 | ≤ 100 | 0 | 0 | 0 |
| 64 | products | 4074 | 95.6 | ≤ 100 | ≤ 250 | ≤ 250 | 60 | 5542 | 0 |

- ⚠ browse × 64 failed 5602 requests; the bench paused 65 s (TIME_WAIT) before the next stage

## browse-direct

the same reads straight to the products service: the gap to `browse` is the gateway's cost.

| VUs | step | ok/s | ok | errors | mean ms | p50 | p90 | p95 | p99 | max |
|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `products.list` | 135.4 | 2031 | 0 | 3.7 | 3.6 | 4.3 | 4.7 | 6.8 | 23.6 |
| 1 | `products.get` | 135.3 | 2030 | 0 | 3.7 | 3.5 | 4.2 | 4.7 | 6.4 | 28.4 |
| 8 | `products.list` | 428.2 | 6426 | 0 | 9.4 | 9.0 | 13.0 | 14.5 | 18.4 | 33.3 |
| 8 | `products.get` | 427.9 | 6421 | 0 | 9.3 | 8.9 | 12.9 | 14.4 | 18.7 | 37.8 |
| 32 | `products.list` | 434.0 | 6522 | 0 | 37.0 | 35.9 | 51.2 | 56.9 | 68.6 | 95.2 |
| 32 | `products.get` | 432.4 | 6499 | 0 | 36.8 | 35.7 | 51.1 | 55.9 | 68.0 | 104.8 |
| 64 | `products.list` | 22.1 | 333 | **4480** (503×4480) | 68.0 | 61.9 | 110.3 | 124.6 | 137.1 | 147.7 |
| 64 | `products.get` | 20.6 | 310 | **4480** (503×4480) | 54.9 | 53.2 | 80.5 | 89.6 | 130.9 | 168.4 |

- ⚠ browse-direct × 64 failed 8960 requests; the bench paused 65 s (TIME_WAIT) before the next stage

## cart

add, read and remove a cart line through raygate (raykv + an rpc to products per add).

| VUs | step | ok/s | ok | errors | mean ms | p50 | p90 | p95 | p99 | max |
|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `cart.add` | 100.4 | 1507 | 0 | 6.7 | 6.1 | 8.5 | 10.1 | 13.4 | 84.8 |
| 1 | `cart.get` | 100.4 | 1507 | 0 | 1.2 | 1.0 | 2.0 | 2.4 | 3.6 | 17.0 |
| 1 | `cart.remove` | 100.4 | 1507 | 0 | 2.0 | 1.9 | 3.0 | 3.4 | 4.8 | 32.8 |
| 8 | `cart.add` | 231.4 | 3476 | 0 | 19.5 | 18.4 | 25.7 | 28.6 | 41.5 | 179.2 |
| 8 | `cart.get` | 231.4 | 3476 | 0 | 5.5 | 4.9 | 9.1 | 10.9 | 16.1 | 83.0 |
| 8 | `cart.remove` | 231.4 | 3476 | 0 | 9.5 | 8.5 | 14.3 | 16.6 | 22.4 | 177.0 |
| 32 | `cart.add` | 44.0 | 671 | **1336** (503×1336) | 58.9 | 57.8 | 78.0 | 84.4 | 103.5 | 122.9 |
| 32 | `cart.get` | 43.5 | 663 | **1344** (503×1344) | 23.4 | 23.0 | 34.4 | 39.6 | 48.4 | 61.6 |
| 32 | `cart.remove` | 42.9 | 654 | **1353** (503×1353) | 35.0 | 34.8 | 48.3 | 52.7 | 60.4 | 78.3 |
| 64 | `cart.add` | 346.1 | 5246 | 0 | 125.8 | 114.6 | 209.2 | 246.8 | 333.8 | 534.9 |
| 64 | `cart.get` | 346.1 | 5246 | 0 | 23.0 | 16.6 | 46.3 | 53.8 | 73.1 | 174.3 |
| 64 | `cart.remove` | 346.1 | 5246 | 0 | 35.3 | 27.5 | 65.6 | 76.0 | 140.4 | 310.0 |

Measured by raygate (upstream time, from its `/metrics` histogram; percentiles are bucket bounds):

| VUs | route | admitted | mean ms | p50 | p95 | p99 | upstream errors | breaker fast-fail | 429 |
|---:|---|---:|---:|---|---|---|---:|---:|---:|
| 1 | cart | 4521 | 3.0 | ≤ 5 | ≤ 10 | ≤ 25 | 0 | 0 | 0 |
| 8 | cart | 10428 | 10.9 | ≤ 10 | ≤ 25 | ≤ 50 | 0 | 0 | 0 |
| 32 | cart | 2025 | 38.5 | ≤ 50 | ≤ 100 | ≤ 100 | 37 | 3996 | 0 |
| 64 | cart | 15738 | 60.4 | ≤ 50 | ≤ 250 | ≤ 500 | 0 | 0 | 0 |

- ⚠ cart × 32 failed 4033 requests; the bench paused 65 s (TIME_WAIT) before the next stage

## purchase

add to cart → checkout → poll the order until the saga settles it (outbox → gRPC → rayq → worker → rayq → consumer).

| VUs | step | ok/s | ok | errors | mean ms | p50 | p90 | p95 | p99 | max |
|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `cart.add` | 1.5 | 22 | 0 | 6.8 | 6.5 | 8.3 | 8.5 | 9.0 | 9.0 |
| 1 | `orders.place` | 1.5 | 22 | 0 | 9.1 | 8.0 | 11.4 | 11.9 | 14.9 | 14.9 |
| 1 | `orders.get` | 6.3 | 95 | 0 | 2.0 | 1.8 | 3.1 | 4.2 | 5.5 | 5.5 |
| 1 | `purchase.to_paid` | 1.3 | 20 | 0 | 698.4 | 616.7 | 1026.1 | 1027.6 | 1032.6 | 1032.6 |
| 1 | `purchase.to_cancelled` | 0.1 | 2 | 0 | 517.8 | 416.7 | 618.9 | 618.9 | 618.9 | 618.9 |
| 8 | `cart.add` | 9.1 | 144 | 0 | 9.9 | 9.1 | 14.9 | 16.0 | 19.7 | 20.9 |
| 8 | `orders.place` | 9.1 | 144 | 0 | 15.8 | 15.4 | 21.7 | 23.8 | 27.0 | 27.2 |
| 8 | `orders.get` | 46.4 | 736 | 0 | 2.0 | 1.7 | 3.0 | 3.7 | 5.1 | 6.8 |
| 8 | `purchase.to_paid` | 8.3 | 131 | 0 | 844.3 | 828.3 | 1227.4 | 1231.6 | 1233.4 | 1235.5 |
| 8 | `purchase.to_cancelled` | 0.8 | 13 | 0 | 890.8 | 830.3 | 1042.3 | 1227.9 | 1227.9 | 1227.9 |
| 32 | `cart.add` | 25.3 | 405 | 0 | 16.0 | 11.0 | 29.0 | 40.7 | 81.2 | 89.7 |
| 32 | `orders.place` | 25.3 | 405 | 0 | 24.8 | 18.1 | 47.0 | 68.8 | 97.6 | 123.4 |
| 32 | `orders.get` | 172.6 | 2761 | 0 | 2.5 | 2.1 | 4.2 | 5.1 | 7.5 | 12.1 |
| 32 | `purchase.to_paid` | 22.8 | 365 | 0 | 1209.5 | 1231.8 | 1448.3 | 1486.6 | 1735.5 | 1929.2 |
| 32 | `purchase.to_cancelled` | 2.5 | 40 | 0 | 1172.6 | 1231.0 | 1456.3 | 1476.5 | 1633.7 | 1633.7 |
| 64 | `cart.add` | 26.5 | 455 | 0 | 25.8 | 13.9 | 54.5 | 119.9 | 172.2 | 185.1 |
| 64 | `orders.place` | 26.5 | 455 | 0 | 40.1 | 22.9 | 119.7 | 175.7 | 202.8 | 268.2 |
| 64 | `orders.get` | 314.3 | 5393 | 0 | 2.8 | 2.3 | 4.9 | 6.1 | 9.3 | 19.2 |
| 64 | `purchase.to_paid` | 23.8 | 409 | 0 | 2249.2 | 2277.0 | 2655.5 | 2667.6 | 2858.0 | 2875.4 |
| 64 | `purchase.to_cancelled` | 2.7 | 46 | 0 | 2212.7 | 2288.1 | 2475.4 | 2481.4 | 2659.9 | 2659.9 |

Measured by raygate (upstream time, from its `/metrics` histogram; percentiles are bucket bounds):

| VUs | route | admitted | mean ms | p50 | p95 | p99 | upstream errors | breaker fast-fail | 429 |
|---:|---|---:|---:|---|---|---|---:|---:|---:|
| 1 | cart | 22 | 6.5 | ≤ 10 | ≤ 10 | ≤ 10 | 0 | 0 | 0 |
| 1 | orders | 117 | 3.0 | ≤ 5 | ≤ 10 | ≤ 25 | 0 | 0 | 0 |
| 8 | cart | 144 | 9.5 | ≤ 10 | ≤ 25 | ≤ 25 | 0 | 0 | 0 |
| 8 | orders | 880 | 3.9 | ≤ 5 | ≤ 25 | ≤ 25 | 0 | 0 | 0 |
| 32 | cart | 405 | 15.4 | ≤ 25 | ≤ 50 | ≤ 100 | 0 | 0 | 0 |
| 32 | orders | 3166 | 4.8 | ≤ 5 | ≤ 25 | ≤ 100 | 0 | 0 | 0 |
| 64 | cart | 455 | 25.0 | ≤ 25 | ≤ 250 | ≤ 250 | 0 | 0 | 0 |
| 64 | orders | 5848 | 5.2 | ≤ 5 | ≤ 25 | ≤ 100 | 0 | 0 | 0 |

Outcomes (every 10th card is declined, so the compensation runs too):

| VUs | purchases/s | paid | cancelled | timeout | checkout failed | peak backlog payment.jobs / payment.results | stock of product 5 |
|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | 1.5 | 20 | 2 | 0 | 0 | 1 / 1 | 200 → 180 (expected 180) |
| 8 | 9.1 | 131 | 13 | 0 | 0 | 8 / 8 | 480 → 349 (expected 349) |
| 32 | 25.3 | 365 | 40 | 0 | 0 | 20 / 14 | 1920 → 1555 (expected 1555) |
| 64 | 26.5 | 409 | 46 | 0 | 0 | 20 / 13 | 3840 → 3431 (expected 3431) |

- ✓ purchase × 1: stock conserved — 200 − 20 units paid = 180
- ✓ purchase × 1: every order settled within 60 s (0 did not)
- ✓ purchase × 8: stock conserved — 480 − 131 units paid = 349
- ✓ purchase × 8: every order settled within 60 s (0 did not)
- ✓ purchase × 32: stock conserved — 1920 − 365 units paid = 1555
- ✓ purchase × 32: every order settled within 60 s (0 did not)
- ✓ purchase × 64: stock conserved — 3840 − 409 units paid = 3431
- ✓ purchase × 64: every order settled within 60 s (0 did not)

## drain

every VU buys one unit of the same product until it sells out: exactly the stock must be sold.

| VUs | step | ok/s | ok | errors | mean ms | p50 | p90 | p95 | p99 | max |
|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|
| 64 | `cart.add` | 23.0 | 564 | 0 | 30.7 | 15.2 | 71.2 | 115.1 | 178.9 | 189.1 |
| 64 | `orders.place` | 20.4 | 500 | 0 | 50.8 | 28.3 | 118.5 | 140.5 | 237.0 | 293.3 |
| 64 | `orders.get` | 308.4 | 7559 | 0 | 7.4 | 4.5 | 17.1 | 20.9 | 29.9 | 70.5 |
| 64 | `purchase.to_paid` | 20.4 | 500 | 0 | 2994.2 | 2511.0 | 4977.5 | 5270.9 | 5659.3 | 5839.9 |

Measured by raygate (upstream time, from its `/metrics` histogram; percentiles are bucket bounds):

| VUs | route | admitted | mean ms | p50 | p95 | p99 | upstream errors | breaker fast-fail | 429 |
|---:|---|---:|---:|---|---|---|---:|---:|---:|
| 64 | cart | 564 | 29.4 | ≤ 25 | ≤ 250 | ≤ 250 | 0 | 0 | 0 |
| 64 | orders | 8059 | 8.7 | ≤ 5 | ≤ 25 | ≤ 250 | 0 | 0 | 0 |

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
| browse | 1 | products 73.2 (84.1) · 37.0 MiB — postgres 41.5 (49.6) · 30.4 MiB — raygate 35.8 (48.8) · 19.3 MiB — cart 9.0 (9.7) · 23.6 MiB — payment 8.9 (9.7) · 19.5 MiB |
| browse | 8 | products 156.5 (184.5) · 39.8 MiB — postgres 132.2 (154.1) · 38.6 MiB — raygate 62.0 (78.0) · 25.7 MiB — cart 8.1 (8.8) · 23.6 MiB — payment 8.0 (9.0) · 19.5 MiB |
| browse | 32 | products 199.9 (236.2) · 43.1 MiB — postgres 156.8 (187.8) · 62.1 MiB — raygate 58.8 (73.8) · 26.9 MiB — mongo 8.7 (25.3) · 172.7 MiB — cart 8.1 (8.9) · 23.6 MiB |
| browse | 64 | products 70.3 (235.2) · 45.4 MiB — postgres 53.3 (187.7) · 76.0 MiB — raygate 40.9 (64.2) · 30.2 MiB — bench-run-a3a6c8426934 11.3 (18.5) · 35.8 MiB — mongo 10.2 (27.5) · 318.7 MiB |
| browse-direct | 1 | products 68.1 (83.3) · 37.1 MiB — postgres 52.0 (60.2) · 30.3 MiB — payment 9.1 (9.8) · 19.5 MiB — cart 9.0 (9.9) · 23.6 MiB — rayq 8.9 (9.4) · 29.1 MiB |
| browse-direct | 8 | products 202.0 (254.3) · 40.2 MiB — postgres 196.5 (231.6) · 39.1 MiB — mongo 8.5 (26.7) · 172.7 MiB — cart 8.2 (9.0) · 23.6 MiB — payment 8.0 (8.4) · 19.5 MiB |
| browse-direct | 32 | products 247.8 (280.2) · 44.4 MiB — postgres 197.5 (225.5) · 66.6 MiB — mongo 11.1 (29.5) · 324.6 MiB — cart 8.2 (9.2) · 23.6 MiB — payment 8.1 (8.9) · 19.5 MiB |
| browse-direct | 64 | products 131.1 (155.8) · 45.7 MiB — bench-run-a3a6c8426934 23.8 (29.0) · 36.1 MiB — postgres 12.8 (85.3) · 27.5 MiB — mongo 9.8 (27.6) · 172.7 MiB — cart 8.5 (9.1) · 23.6 MiB |
| cart | 1 | cart 61.7 (89.8) · 26.7 MiB — raygate 54.3 (79.8) · 28.0 MiB — raykv 53.0 (72.6) · 18.1 MiB — products 42.9 (98.4) · 37.0 MiB — postgres 29.6 (78.2) · 28.5 MiB |
| cart | 8 | cart 130.9 (162.1) · 32.1 MiB — raygate 72.7 (84.4) · 28.9 MiB — products 67.8 (100.1) · 37.4 MiB — postgres 60.9 (81.1) · 32.8 MiB — raykv 59.5 (74.3) · 18.3 MiB |
| cart | 32 | raygate 28.1 (45.3) · 29.1 MiB — mongo 9.8 (44.8) · 320.5 MiB — cart 9.2 (20.6) · 31.0 MiB — bench-run-a3a6c8426934 8.9 (10.0) · 35.2 MiB — products 7.7 (8.8) · 37.3 MiB |
| cart | 64 | cart 125.7 (176.5) · 31.0 MiB — products 81.8 (119.4) · 37.3 MiB — postgres 77.2 (104.1) · 36.0 MiB — raygate 56.2 (72.5) · 30.4 MiB — raykv 48.2 (58.5) · 18.4 MiB |
| purchase | 1 | payment 11.6 (13.0) · 19.6 MiB — products 9.2 (16.5) · 36.5 MiB — mongo 8.2 (30.9) · 315.0 MiB — cart 8.1 (9.0) · 23.8 MiB — raygate 7.8 (11.8) · 28.5 MiB |
| purchase | 8 | payment 27.7 (38.4) · 19.8 MiB — products 14.9 (18.3) · 36.4 MiB — raygate 14.8 (18.1) · 28.0 MiB — cart 10.3 (12.8) · 23.9 MiB — rayq 9.9 (12.1) · 29.4 MiB |
| purchase | 32 | payment 72.0 (91.0) · 20.2 MiB — raygate 36.8 (44.1) · 29.9 MiB — products 34.4 (50.8) · 36.6 MiB — postgres 25.6 (48.9) · 28.2 MiB — orders 22.2 (23.8) · 31.6 MiB |
| purchase | 64 | payment 70.5 (92.8) · 20.6 MiB — raygate 52.6 (60.3) · 30.6 MiB — orders 26.6 (32.4) · 33.1 MiB — products 25.0 (35.7) · 36.8 MiB — postgres 16.6 (23.9) · 30.1 MiB |
| drain | 64 | payment 66.8 (90.4) · 20.1 MiB — raygate 50.4 (59.5) · 30.5 MiB — orders 31.0 (38.0) · 32.2 MiB — products 25.5 (31.4) · 37.2 MiB — mysql 23.1 (31.3) · 537.9 MiB |
