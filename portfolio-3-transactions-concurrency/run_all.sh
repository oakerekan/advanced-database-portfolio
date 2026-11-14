#!/usr/bin/env bash
# MIT 8103 - Portfolio 3: run everything from an empty database.
# Requires PostgreSQL 14+ (psql, createdb, dropdb on PATH) and Python 3.
# Set PGHOST / PGUSER / PGPASSWORD first if needed. Takes about 30 seconds.
set -euo pipefail
cd "$(dirname "$0")"
export PGDATABASE=lagoon_p3
mkdir -p results
PY=$(command -v python3 >/dev/null 2>&1 && python3 -c 1 >/dev/null 2>&1 && echo python3 || echo python)

dropdb --if-exists lagoon_p3
createdb lagoon_p3
psql -X -q -f ../portfolio-1-database-design/schema.sql 2>/dev/null
psql -X -q -f setup.sql

# Part A: single-session transactions
psql -X -q -f seed.sql
psql -X -f 01_transactions.sql > results/01_transactions_output.txt 2>&1
echo "Part A written to results/01_transactions_output.txt"

# Part B: two-session concurrency scenarios
$PY run_concurrency.py
