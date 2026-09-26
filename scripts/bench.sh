#!/usr/bin/env bash
# The benchmark around `raymart bench` (make bench / make bench-quick). Arguments go to the
# load generator (--scenarios, --stages, --duration, --declined-every, --drain-stock).
#
#  1. swaps raygate to config/raygate.bench.toml (no per-IP rate limits) for the run, and puts
#     the normal config back on exit, whatever happens;
#  2. samples `docker stats` of this compose project's containers (the load generator
#     included) until the run ends — it stops by itself, nothing is killed;
#  3. runs the native load generator inside the compose network;
#  4. adds the resource usage per stage to the report.
set -euo pipefail
cd "$(dirname "$0")/.."

compose="docker compose"
name="$(date +%Y%m%d-%H%M%S)"
out="perf/results/$name"
mkdir -p "$out"

$compose --profile bench build -q bench
$compose -f docker-compose.yml -f docker-compose.bench.yml up -d --wait raygate >/dev/null
restore() {
    $compose up -d --wait raygate >/dev/null 2>&1 || echo "warning: raygate not restored; run make up" >&2
}
trap restore EXIT

{
    printf 'Host: %s, %s cores · ' "$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)" "$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
    docker info --format 'Docker: {{.NCPU}} CPUs, {{.MemTotal}} bytes of memory, {{.ServerVersion}}' \
        | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/ && $(i+1) == "bytes") { $i = sprintf("%.1f GiB", $i / 1073741824); $(i+1) = "" } print }' \
        | tr -s ' '
} > "$out/env.txt"

(
    while [ ! -f "$out/.done" ]; do
        ids=$(docker ps -q --filter label=com.docker.compose.project=raymart)
        ts=$(date +%s)
        [ -n "$ids" ] && docker stats --no-stream --format "$ts,{{.Name}},{{.CPUPerc}},{{.MemUsage}}" $ids >> "$out/docker-stats.csv" 2>/dev/null || true
    done
) &
sampler=$!

rc=0
$compose --profile bench run --rm bench bench --out "/out/$name" "$@" || rc=$?
touch "$out/.done"
wait "$sampler" || true
$compose --profile bench run --rm bench bench-resources "/out/$name" || true
rm -f "$out/.done"
echo "report: $out/report.md"
exit "$rc"
