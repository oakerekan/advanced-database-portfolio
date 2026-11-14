# Portfolio 3: Transactions and Concurrency

**Case study:** Laguna Care Specialist Hospital
**DBMS:** PostgreSQL 15, using the schema from Portfolio 1

## 1. Aim

In a hospital, many staff change the same data at the same moment: receptionists book appointments, pharmacists dispense from shared stock, nurses manage beds. This portfolio shows:
1. **Atomicity:** COMMIT, ROLLBACK and SAVEPOINT on real hospital operations.
2. **Concurrency problems:** five classic anomalies reproduced with two real database sessions running at the same time.
3. **Control mechanisms:** how locks, isolation levels, constraints and lock ordering prevent each one.

## 2. Files

| File | Purpose |
|---|---|
| `setup.sql` | Adds `log()` (a timestamped message) and `dispense_item()`, the pharmacy's dispense operation |
| `seed.sql` | Small, known starting data: 2 branches, 2 doctors, 3 patients, 10 Coartem per branch, 2 ICU beds. Every test resets to this. |
| `01_transactions.sql` | **Part A:** single-session COMMIT, ROLLBACK and SAVEPOINT |
| `scenarios/sNN_*_A.sql`, `_B.sql` | **Part B:** two sessions per scenario (e.g. two receptionists) |
| `scenarios/sNN_*_check.sql` | Shows the final state and a one-line RESULT |
| `run_concurrency.py` | Starts session A and B as two separate psql connections, slightly offset in time, and records a timeline |
| `run_all.sh` | Runs everything from an empty database (about 30 seconds) |
| `results/` | `01_transactions_output.txt`, one timeline file per scenario, and `summary.md` |

**How to run:** `./run_all.sh` (with `PGHOST`, `PGUSER` and `PGPASSWORD` set, as for Portfolio 2)

## 3. Part A: single-session transactions

Output: `results/01_transactions_output.txt`

| Test | What happens | What it proves |
|---|---|---|
| **A1: COMMIT** | Two drugs are dispensed for Chinedu inside one `BEGIN ... COMMIT`. Stock drops (Coartem 10→4, Paracetamol 100→90), both prescription lines are marked dispensed, and two drug lines are added to his invoice. | Related changes to 4 tables succeed together. |
| **A2: Atomicity** | A second prescription needs 6 Coartem but only 4 remain. Paracetamol is dispensed first; inside the transaction its stock reads 80. Then `dispense_item()` raises "Insufficient stock". | After ROLLBACK, Paracetamol is back at **90** and nothing was dispensed or billed. No half-dispensed prescription can exist. |
| **A3: Explicit ROLLBACK** | A cashier mistypes a ₦99,999 payment. Inside the transaction the invoice shows ₦109,999 paid. | After ROLLBACK it is back to ₦10,000. Uncommitted work can be abandoned. |
| **A4: SAVEPOINT** | In one transaction, Ngozi gets an emergency encounter (step 1), then admission to ICU-01, which is occupied, so the `no_bed_double_occupancy` constraint fires. `ROLLBACK TO SAVEPOINT` undoes only that step; she is admitted to ICU-02 and the transaction commits. | Partial rollback: step 1 is kept and only the failed step is retried. |

Points worth noticing in the output:
- **Errors abort the rest of the transaction.** After an error, PostgreSQL refuses every further statement ("current transaction is aborted") until ROLLBACK.
- **Sequences are not transactional.** The failed ICU-01 admission still used up `admission_id` 2, so Ngozi's admission is number 3. Gaps in IDs are normal and must not be relied on.
- **`dispense_item()` never reads stock and then writes a calculated value.** It uses a single conditional statement, `UPDATE ... SET quantity = quantity - n WHERE quantity >= n`. Part B, scenario s03, shows why that matters.

## 4. Part B: concurrency scenarios

Each scenario runs two sessions as two separate database connections. Session B starts 0.3–0.5 s after A. Both use `pg_sleep()` to hold a transaction open, which simulates a user pausing between steps. The timeline in each `results/sNN_*.txt` file shows exactly when each session waited, failed or committed.

| # | Scenario | Isolation | Observed result |
|---|---|---|---|
| s01 | Two receptionists book **overlapping slots** for Dr Okafor | Read Committed | B **waited 1.5 s** for A, then was rejected by `no_doctor_double_booking`. 1 booking saved. |
| s02 | Same, but A **rolls back** | Read Committed | B waited, then succeeded as soon as A rolled back. |
| s03 | **Lost update:** two pharmacists read stock = 10, then write `10 - 3` and `10 - 4` | Read Committed | Stock ended at **6 instead of 3**. 7 strips left the shelf but only 4 were deducted. |
| s04 | Fix 1: `SELECT ... FOR UPDATE` | Read Committed | B's read **blocked** until A committed, then saw 7 and wrote 3. Correct. |
| s05 | Fix 2: **optimistic** | Repeatable Read | B's UPDATE failed with *could not serialize access due to concurrent update* (SQLSTATE 40001). B **retried**, read 7 and wrote 3. Correct. |
| s06 | **Non-repeatable read:** an end-of-day report reads takings twice while a payment is posted | Read Committed | The two reads in one transaction **disagreed**: ₦10,000, then ₦30,000. |
| s07 | Same report | Repeatable Read | Both reads showed ₦10,000, one consistent snapshot. A new transaction then saw ₦30,000. |
| s08 | **Write skew:** rule "ICU keeps ≥ 1 bed in service". Two nurses each see 2 beds and each take a *different* bed out. | Repeatable Read | Both committed, leaving **0 ICU beds in service**. The rule was broken without any row being updated twice. |
| s09 | Same two nurses | **Serializable** | PostgreSQL aborted Nurse B: *could not serialize access due to read/write dependencies*. 1 bed stays in service. |
| s10 | **Deadlock:** two stock transfers between branches lock rows in opposite order | Read Committed | After ~1 s (`deadlock_timeout`) PostgreSQL reported **deadlock detected** and aborted one transfer. Total stock stayed 20. |
| s11 | Fix: every transfer locks rows in the **same order** (lowest `branch_id` first) | Read Committed | B simply waited for A. **Both** transfers applied: Ikeja 11, Lekki 9, total 20. |

## 5. Analysis

### Concurrency control used by PostgreSQL
- **MVCC (multi-version concurrency control):** readers never block writers and writers never block readers, because each transaction reads a snapshot. This is why s06 and s07 never waited. The isolation level decides how often the snapshot is taken: per *statement* in Read Committed, once per *transaction* in Repeatable Read and Serializable.
- **Row locks:** they are taken by UPDATE, DELETE and `SELECT ... FOR UPDATE`, and held until COMMIT or ROLLBACK. Writers to the same row queue up, as in s04 and s11.
- **Constraint-level protection:** the `EXCLUDE` constraint from Portfolio 1 made B wait in s01 and s02 even though B was inserting a *new* row. PostgreSQL must wait to learn whether A's conflicting row will commit or roll back. s02 proves the wait is real: when A rolled back, B's insert succeeded.

### Choosing a fix for each problem

| Problem | Best fix in this system | Why |
|---|---|---|
| Double booking | Exclusion constraint (s01) | It holds whatever the application does, at any isolation level. A rule enforced in application code alone can be bypassed. |
| Lost update on stock | Atomic `UPDATE ... SET quantity = quantity - n WHERE quantity >= n` (used in `dispense_item`); otherwise `FOR UPDATE` (s04) | No read-then-write gap at all. `FOR UPDATE` is right when the application must look at the value before deciding. |
| Inconsistent reports | Repeatable Read for report transactions (s07) | Cheap: readers take no locks and get one consistent snapshot. |
| Rules spanning several rows (write skew) | Serializable, plus a retry loop (s09) | No single row conflicts, so row locks and Repeatable Read cannot see the problem. Only Serializable (Serializable Snapshot Isolation) detects the read/write dependency. |
| Deadlock | Consistent lock ordering (s11) | Prevents deadlocks instead of relying on detection, which wastes ~1 s and aborts work. |

### Trade-offs
- **Higher isolation means more aborted transactions.** Repeatable Read and Serializable never block more than Read Committed. Instead they *abort* transactions with SQLSTATE 40001, so the application **must retry** (s05). Serializable is used only where a multi-row rule matters, such as bed and roster rules, not for every query.
- **Pessimistic locking (`FOR UPDATE`) serialises the users.** In s04, Pharmacist B waited 1 s for A. That's fine for a single stock row, but a lock held while a user thinks would block the whole pharmacy queue. Transactions must be short and never wait for user input.
- **Lost-update risk depends on how the application is written.** s03 happened at the default isolation level because the application *computed* the new value itself. This is the most likely real-world bug of all the scenarios.

## 6. Notes on the method
- `pg_sleep()` stands in for the time a real user or application spends between statements. It makes rare timing problems happen every time, so they can be demonstrated.
- PostgreSQL never allows *dirty reads*, even if Read Uncommitted is requested, so that anomaly cannot be shown.
- Durability (the D in ACID) is provided by the write-ahead log: a COMMIT returns only once its WAL record is on disk. Portfolio 5 builds on the same WAL for replication.
