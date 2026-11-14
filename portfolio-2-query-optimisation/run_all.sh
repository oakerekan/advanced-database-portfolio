#!/usr/bin/env bash
# MIT 8103 - Portfolio 2: full experiment, from empty database to comparison table.
# Requires: PostgreSQL 14+ (psql on PATH), Python 3.
# Set PGHOST / PGUSER / PGPASSWORD for your server first if needed.
set -euo pipefail
cd "$(dirname "$0")"
export PGDATABASE=laguna_care
mkdir -p results
# Windows usually names Python 'python'; macOS/Linux use 'python3'
PY=$(command -v python3 >/dev/null 2>&1 && python3 -c 1 >/dev/null 2>&1 && echo python3 || echo python)

dropdb --if-exists laguna_care
createdb laguna_care
psql -X -q -f ../portfolio-1-database-design/schema.sql
psql -X -v ON_ERROR_STOP=1 -f generate_data.sql > results/data_load_output.txt 2>&1   # errors are saved too, and stop the script

$PY run_benchmark.py 1-baseline  queries.sql            # no extra indexes
psql -X -q -f optimisations.sql                             # add indexes + materialized view
$PY run_benchmark.py 2-indexed   queries.sql            # same SQL, new indexes
$PY run_benchmark.py 3-optimised queries_optimised.sql  # rewritten Q2, Q5, Q6, Q7
$PY run_benchmark.py --compare

# Size of each new index vs. its table
psql -X -c "SELECT indexrelname AS index, relname AS table,
                   pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
                   pg_size_pretty(pg_relation_size(relid))      AS table_size
            FROM pg_stat_user_indexes
            WHERE schemaname = 'hospital' AND indexrelname LIKE 'idx_%'
            ORDER BY indexrelname;" > results/index_sizes.txt
cat results/index_sizes.txt
