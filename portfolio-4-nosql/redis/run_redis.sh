#!/usr/bin/env bash
# MIT 8103 - Portfolio 4: run the Redis key-value demo.
# Needs a running Redis server (default localhost:6379) and redis-cli.
# Windows: use Memurai (Redis-compatible), Redis under WSL, or a free Redis Cloud database
#          (then: export REDIS_URL=redis://default:PASSWORD@HOST:PORT).
# Only keys starting with "lc:" are touched.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p results
if [ -n "${REDIS_URL:-}" ]; then CLI=(redis-cli -u "$REDIS_URL"); else CLI=(redis-cli); fi
"${CLI[@]}" < redis/hospital_realtime.redis | tee results/redis_output.txt
