#!/usr/bin/env bash
# =====================================================================
# MIT 8103 - Portfolio 5, Part B: horizontal sharding by branch
# Laguna Care Specialist Hospital
#
# Builds 4 PostgreSQL servers on this computer:
#   coordinator  localhost:5440  - the only server applications connect to
#   shard_ikj    localhost:5441  - holds Ikeja's clinical encounters
#   shard_lki    localhost:5442  - holds Lekki's
#   shard_yab    localhost:5443  - holds Yaba's
# The coordinator has a table PARTITIONED BY LIST (branch_id) whose
# partitions are FOREIGN TABLES on the shards (postgres_fdw), so SQL is
# routed to the right shard automatically.
#
# Needs PostgreSQL 14+ (postgres_fdw ships with PostgreSQL). Ports 5440-5443.
# Run as a normal (non-administrator) user. Takes about 1 minute.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p results
exec > >(tee results/sharding_output.txt) 2>&1

BASE="$PWD/cluster/sharding"
PSQL=(psql -X -h localhost -U postgres)
sql()    { local port=$1 db=$2; shift 2; "${PSQL[@]}" -p "$port" -d "$db" "$@"; }
banner() { echo; echo "==================== $* ===================="; }
NODES=(coordinator:5440 shard_ikj:5441 shard_lki:5442 shard_yab:5443)

for n in "${NODES[@]}"; do pg_ctl -D "$BASE/${n%%:*}" -m immediate -w stop >/dev/null 2>&1 || true; done
rm -rf "$BASE"; mkdir -p "$BASE"

banner "1. Start 4 servers"
for n in "${NODES[@]}"; do
  name=${n%%:*}; port=${n##*:}
  initdb -D "$BASE/$name" -U postgres -A trust >/dev/null
  printf "port = %s\nlisten_addresses = 'localhost'\n" "$port" >> "$BASE/$name/postgresql.conf"
  pg_ctl -D "$BASE/$name" -l "$BASE/$name.log" -w start >/dev/null
  echo "$name running on port $port"
done

banner "2. Each shard stores ONLY its own branch (enforced by a CHECK constraint)"
i=1
for n in shard_ikj:5441 shard_lki:5442 shard_yab:5443; do
  port=${n##*:}
  sql "$port" postgres -q -c "CREATE DATABASE laguna_shard"
  sql "$port" laguna_shard -q -f sharding/shard_table.sql -v branch="$i"
  echo "${n%%:*}: table encounter_record created, CHECK (branch_id = $i)"
  i=$((i + 1))
done

banner "3. Coordinator: partitioned table whose partitions live on the shards"
sql 5440 postgres -q -c "CREATE DATABASE laguna_care"
sql 5440 laguna_care -q -f sharding/coordinator.sql
sql 5440 laguna_care -c "\d+ encounter_record" | sed -n '/Partition key/,$p'

banner "4. Load 30,000 encounters THROUGH the coordinator (rows are routed by branch_id)"
sql 5440 laguna_care -q -f sharding/load_data.sql
echo "Rows stored on each shard (asked directly, bypassing the coordinator):"
for n in shard_ikj:5441 shard_lki:5442 shard_yab:5443; do
  echo "  ${n%%:*}: $(sql "${n##*:}" laguna_shard -At -c "SELECT count(*) || ' rows, branch_id(s) = ' || string_agg(DISTINCT branch_id::text, ',') FROM encounter_record")"
done

banner "5. Query for ONE branch touches ONE shard (partition pruning)"
sql 5440 laguna_care -c "EXPLAIN (VERBOSE, COSTS OFF)
  SELECT count(*), sum(amount) FROM encounter_record
  WHERE branch_id = 2 AND started_at >= '2026-01-01'"
sql 5440 laguna_care -c "SELECT count(*) AS lekki_visits_2026, sum(amount) AS lekki_billed_2026 FROM encounter_record
                         WHERE branch_id = 2 AND started_at >= '2026-01-01'"

banner "6. Group-wide report: each shard aggregates its own rows in parallel, the coordinator combines them"
sql 5440 laguna_care -q -c "SET enable_partitionwise_aggregate = on" -c "EXPLAIN (VERBOSE, COSTS OFF)
  SELECT branch_id, count(*), sum(amount) FROM encounter_record GROUP BY branch_id"
sql 5440 laguna_care -c "SET enable_partitionwise_aggregate = on" -c "SELECT b.branch_code, r.visits, r.billed
  FROM (SELECT branch_id, count(*) AS visits, sum(amount) AS billed FROM encounter_record GROUP BY branch_id) r
  JOIN branch b USING (branch_id) ORDER BY branch_id"

banner "7. Query NOT on the shard key: a patient's history must ask every shard (scatter-gather)"
sql 5440 laguna_care -c "EXPLAIN (COSTS OFF)
  SELECT * FROM encounter_record WHERE hospital_no = 'LCH-0000013'"
sql 5440 laguna_care -c "SELECT branch_id, started_at::date, encounter_type, primary_dx FROM encounter_record
                         WHERE hospital_no = 'LCH-0000013' ORDER BY started_at"

banner "8. A wrong-branch row is rejected by the shard itself"
sql 5441 laguna_shard -c "INSERT INTO encounter_record VALUES (999999, 2, 'LCH-0000001', now(), 'outpatient', 'B54', 10000)" \
  || echo "-> Ikeja shard refused a Lekki row"

banner "9. Partial failure: the Lekki shard goes down"
pg_ctl -D "$BASE/shard_lki" -m immediate -w stop >/dev/null
echo "shard_lki stopped"
echo "Ikeja query (does not need Lekki):"
sql 5440 laguna_care -c "SELECT count(*) AS ikeja_visits FROM encounter_record WHERE branch_id = 1"
echo "Group-wide query (needs every shard):"
sql 5440 laguna_care -c "SELECT count(*) FROM encounter_record" 2>&1 | head -2 || true
echo "-> Ikeja and Yaba keep working; only Lekki's data and group-wide reports are unavailable."
pg_ctl -D "$BASE/shard_lki" -l "$BASE/shard_lki.log" -w start >/dev/null
echo "shard_lki restarted; group-wide count = $(sql 5440 laguna_care -At -c 'SELECT count(*) FROM encounter_record')"

banner "Done. Nodes are left running; stop them with ./03_stop_all.sh"
