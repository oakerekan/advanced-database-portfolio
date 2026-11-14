#!/usr/bin/env bash
# =====================================================================
# MIT 8103 - Portfolio 5, Part A: replication, consistency and failover
# Laguna Care Specialist Hospital
#
# Builds a 3-node PostgreSQL cluster on this computer:
#   primary   localhost:5433  - Ikeja data centre, accepts writes
#   replica1  localhost:5434  - SYNCHRONOUS standby (Lekki)
#   replica2  localhost:5435  - ASYNCHRONOUS standby (Yaba, reporting)
# then demonstrates read scaling, read-only standbys, the consistency vs
# availability trade-off of synchronous replication, and failover.
#
# Needs PostgreSQL 14+ binaries on PATH (initdb, pg_ctl, pg_basebackup, psql).
# Uses ports 5433-5435 only, and its own data folders under cluster/.
# Run as a normal (non-administrator) user. Takes about 1 minute.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p results
exec > >(tee results/replication_output.txt) 2>&1

BASE="$PWD/cluster/replication"
PSQL=(psql -X -h localhost -U postgres)
sql()    { local port=$1 db=$2; shift 2; "${PSQL[@]}" -p "$port" -d "$db" "$@"; }
banner() { echo; echo "==================== $* ===================="; }
start()  { pg_ctl -D "$BASE/$1" -l "$BASE/$1.log" -w start >/dev/null; }
stop()   { pg_ctl -D "$BASE/$1" -m "${2:-fast}" -w stop >/dev/null 2>&1 || true; }
wait_caught_up() {   # wait until every standby has replayed everything the primary wrote
  local port=$1
  for _ in $(seq 1 50); do
    if [ "$(sql "$port" postgres -At -c "SELECT count(*) FROM pg_stat_replication WHERE replay_lsn IS DISTINCT FROM pg_current_wal_lsn()")" = "0" ]; then return 0; fi
    sleep 0.2
  done
}

# ---------- clean start ----------
for n in primary replica1 replica2; do stop "$n" immediate; done
rm -rf "$BASE"; mkdir -p "$BASE"

banner "1. Create the primary (port 5433)"
initdb -D "$BASE/primary" -U postgres -A trust >/dev/null
cat >> "$BASE/primary/postgresql.conf" <<EOF
port = 5433
listen_addresses = 'localhost'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
synchronous_commit = on
EOF
start primary
sql 5433 postgres -q -c "CREATE DATABASE laguna_care"
sql 5433 laguna_care -q -f ../portfolio-1-database-design/schema.sql 2>/dev/null
sql 5433 laguna_care -q -f ../portfolio-3-transactions-concurrency/seed.sql
echo "primary running; hospital schema + seed data loaded"

banner "2. Clone two standbys with pg_basebackup (physical copy + WAL streaming)"
for i in 1 2; do
  pg_basebackup -h localhost -p 5433 -U postgres -D "$BASE/replica$i" -X stream -R -C -S "replica${i}_slot"
  echo "port = 543$((3 + i))" >> "$BASE/replica$i/postgresql.conf"
  echo "primary_conninfo = 'host=localhost port=5433 user=postgres application_name=replica$i'" >> "$BASE/replica$i/postgresql.auto.conf"
  start "replica$i"
  echo "replica$i running on port 543$((3 + i))"
done
sleep 1
# Only now make replica1 synchronous: if it were set before the standby existed,
# every commit on the primary would wait for a standby that is not there.
sql 5433 postgres -q -c "ALTER SYSTEM SET synchronous_standby_names = 'replica1'" -c "SELECT pg_reload_conf()" >/dev/null
echo "synchronous_standby_names = 'replica1' (every commit must be confirmed by replica1)"

banner "3. Replication status, seen from the primary"
sql 5433 postgres -c "SELECT application_name, state, sync_state, sent_lsn, replay_lsn FROM pg_stat_replication ORDER BY 1"
for p in 5433 5434 5435; do
  echo "port $p in recovery (read-only standby)? $(sql $p postgres -At -c 'SELECT pg_is_in_recovery()')"
done

banner "4. Write on the primary, read the same row on both standbys"
sql 5433 laguna_care -q -c "INSERT INTO hospital.patient (hospital_no, home_branch_id, first_name, last_name, date_of_birth, sex, phone)
                            VALUES ('LCH-0005001', 1, 'Tolu', 'Adeyemi', '1990-02-14', 'F', '08031112222')"
echo "inserted LCH-0005001 on the primary"
sleep 0.5
for p in 5434 5435; do
  echo "port $p sees: $(sql $p laguna_care -At -c "SELECT hospital_no || ' ' || first_name || ' ' || last_name FROM hospital.patient WHERE hospital_no = 'LCH-0005001'")"
done

banner "5. Standbys are read-only"
sql 5434 laguna_care -c "INSERT INTO hospital.patient (hospital_no, home_branch_id, first_name, last_name, date_of_birth, sex, phone)
                         VALUES ('LCH-0005002', 2, 'Should', 'Fail', '1990-01-01', 'M', '080')" || echo "-> write on replica1 rejected, as expected"

banner "6. Consistency vs availability: the synchronous standby goes down"
stop replica1
echo "replica1 stopped. A receptionist registers a patient on the primary (in the background)..."
( sql 5433 laguna_care -c "INSERT INTO hospital.patient (hospital_no, home_branch_id, first_name, last_name, date_of_birth, sex, phone)
      VALUES ('LCH-0005003', 1, 'Waits', 'ForSync', '1985-05-05', 'M', '08030000003')"; echo "receptionist's client returned" ) &
CLIENT=$!
sleep 3
echo "3 seconds later the client is still waiting. What is it waiting for?"
sql 5433 postgres -c "SELECT pid, state, wait_event_type, wait_event, left(query, 45) AS query
                      FROM pg_stat_activity WHERE wait_event = 'SyncRep'"
echo "The receptionist gives up (simulated with pg_cancel_backend):"
sql 5433 postgres -At -c "SELECT pg_cancel_backend(pid) FROM pg_stat_activity WHERE wait_event = 'SyncRep'" >/dev/null
wait $CLIENT || true
echo "Is LCH-0005003 on the primary? $(sql 5433 laguna_care -At -c "SELECT count(*) FROM hospital.patient WHERE hospital_no='LCH-0005003'") row(s)"
echo "-> PostgreSQL chose CONSISTENCY over AVAILABILITY: it would not report success until the synchronous"
echo "   standby confirmed. When cancelled, the row is committed locally but was NOT confirmed as replicated."

echo
echo "Switch to QUORUM commit: any 1 of (replica1, replica2) may confirm"
sql 5433 postgres -q -c "ALTER SYSTEM SET synchronous_standby_names = 'ANY 1 (replica1, replica2)'" -c "SELECT pg_reload_conf()" >/dev/null
sleep 0.5
sql 5433 laguna_care -c "SET statement_timeout = '3s'" \
  -c "INSERT INTO hospital.patient (hospital_no, home_branch_id, first_name, last_name, date_of_birth, sex, phone)
      VALUES ('LCH-0005004', 1, 'Quorum', 'Commit', '1985-05-05', 'F', '08030000004')" \
  && echo "-> committed immediately: replica2 confirmed it although replica1 is down"
sql 5433 postgres -c "SELECT application_name, state, sync_state FROM pg_stat_replication ORDER BY 1"

echo
echo "Restart replica1: it catches up automatically from its replication slot"
start replica1
sleep 1
wait_caught_up 5433
echo "replica1 now has $(sql 5434 laguna_care -At -c "SELECT count(*) FROM hospital.patient WHERE hospital_no IN ('LCH-0005003','LCH-0005004')") of the 2 rows written while it was down"

banner "7. Failover: the primary crashes, replica1 is promoted"
sql 5433 postgres -q -c "ALTER SYSTEM SET synchronous_standby_names = 'replica1'" -c "SELECT pg_reload_conf()" >/dev/null
sql 5433 laguna_care -q -c "INSERT INTO hospital.appointment (patient_id, doctor_id, branch_id, slot, status, reason)
                            VALUES (1, 1, 1, '[2026-12-02 09:00+01, 2026-12-02 09:30+01)', 'booked', 'Booked just before the crash')"
echo "appointment committed on the primary (confirmed by synchronous replica1)"
wait_caught_up 5433
stop primary immediate
echo "primary killed (pg_ctl stop -m immediate = simulated crash)"
"${PSQL[@]}" -p 5433 -d postgres -c "SELECT 1" 2>&1 | head -1 || true

pg_ctl -D "$BASE/replica1" -w promote >/dev/null
echo "replica1 promoted"
echo "replica1 (port 5434) in recovery? $(sql 5434 postgres -At -c 'SELECT pg_is_in_recovery()')  -> it is now the primary"
echo "appointment booked just before the crash present on the new primary? $(sql 5434 laguna_care -At -c "SELECT count(*) FROM hospital.appointment WHERE reason = 'Booked just before the crash'") row(s) -> no data lost"
sql 5434 laguna_care -q -c "INSERT INTO hospital.patient (hospital_no, home_branch_id, first_name, last_name, date_of_birth, sex, phone)
                            VALUES ('LCH-0005005', 2, 'After', 'Failover', '1999-09-09', 'F', '08030000005')"
echo "new write accepted on the new primary (LCH-0005005)"

echo
echo "Re-point replica2 at the new primary"
sql 5434 postgres -q -c "SELECT pg_create_physical_replication_slot('replica2_slot')" >/dev/null
sql 5435 postgres -q -c "ALTER SYSTEM SET primary_conninfo = 'host=localhost port=5434 user=postgres application_name=replica2'" -c "SELECT pg_reload_conf()" >/dev/null
sleep 2
wait_caught_up 5434
sql 5434 postgres -c "SELECT application_name, state, sync_state FROM pg_stat_replication"
echo "replica2 sees the post-failover patient? $(sql 5435 laguna_care -At -c "SELECT count(*) FROM hospital.patient WHERE hospital_no = 'LCH-0005005'") row(s)"
echo "timeline: new primary writes WAL file $(sql 5434 postgres -At -c 'SELECT pg_walfile_name(pg_current_wal_lsn())') (first 8 hex digits = timeline; the promotion started timeline 2)"

banner "Done. Nodes are left running; stop them with ./03_stop_all.sh"
