# Portfolio 2: Query Processing and Optimisation

**Case study:** Laguna Care Specialist Hospital (3 branches, Lagos)
**DBMS:** PostgreSQL 15 (results below from my laptop, PostgreSQL 15.14 on Windows), using the schema from Portfolio 1

## 1. Aim

Hospital staff run the same few queries all day: looking up a patient, listing today's clinic, taking payments. This portfolio:
1. Loads realistic data volumes.
2. Measures 8 everyday hospital queries.
3. Reads their execution plans to find out *why* they are slow.
4. Fixes them with indexes, query rewrites and a materialized view.
5. Checks that every optimised query still returns exactly the same result.

## 2. Files

| File | Purpose |
|---|---|
| `generate_data.sql` | Loads about 3.3 million rows of fictitious data (fixed random seed, so it can be repeated) |
| `queries.sql` | The 8 workload queries in their original form |
| `optimisations.sql` | 8 new indexes and 1 materialized view, each with its reason |
| `queries_optimised.sql` | The same queries, with Q2, Q5, Q6 and Q7 rewritten |
| `run_benchmark.py` | Times each query (median of 5 runs after 1 warm-up) and saves its `EXPLAIN (ANALYZE, BUFFERS)` plan and its result |
| `run_all.sh` | Runs the whole experiment from an empty database |
| `results/1-baseline/`, `2-indexed/`, `3-optimised/` | One plan file (`Qn_plan.txt`) and one result file (`Qn_result.txt`) per query, per phase |
| `results/comparison.md` | The final timing table |
| `results/index_sizes.txt` | Storage cost of each new index |

**How to run:** `PGHOST=localhost PGUSER=postgres ./run_all.sh` (about 3-10 minutes on a laptop; the data load is silent)

## 3. Test data

| Table | Rows | | Table | Rows |
|---|---:|---|---|---:|
| invoice_item | 780,482 | | invoice | 287,251 |
| diagnosis | 357,858 | | encounter | 275,251 |
| prescription_item | 331,261 | | payment | 258,809 |
| appointment | 300,000 | | lab_request | 165,173 |
| patient | 60,000 | | admission | 12,000 |

The data is generated, not copied from a real hospital, so it contains no real patient information. It is shaped to behave like real data:
- **Skewed diagnoses:** malaria and hypertension are the most common.
- **Branch sizes:** half of patients are registered at Ikeja.
- **Visiting doctors:** 15% of appointments are at a branch other than the doctor's home branch.
- **Valid by construction:** appointments and bed stays never overlap, so all Portfolio 1 constraints still pass.

## 4. Results

| Query | Task | Baseline (ms) | + Indexes (ms) | + Rewrite (ms) | Speed-up | Same result? |
|---|---|---:|---:|---:|---:|:---:|
| Q1 | Patient history (visits, diagnoses, drugs) | 113.12 | 0.81 | 0.62 | 184x | yes |
| Q2 | One doctor's schedule for a day | 58.97 | 51.43 | 1.39 | 43x | yes |
| Q3 | Branch clinic list for a day | 56.35 | 2.47 | 1.79 | 32x | yes |
| Q4 | Patient search by name | 27.35 | 0.98 | 0.82 | 33x | yes |
| Q5 | Cashier end-of-day takings | 46.57 | 48.97 | 2.45 | 19x | yes |
| Q6 | Monthly revenue per branch, 2025 | 264.64 | 257.16 | 0.38 | 706x | yes |
| Q7 | A patient's outstanding invoices | 744.20 | 670.94 | 1.00 | 746x | yes |
| Q8 | Urgent lab tests still waiting | 40.04 | 1.30 | 1.83 | 22x | yes |

**How to read the table:**
- **Times** are the median of 5 warm-cache runs on a single machine. The *ratios* matter more than the exact milliseconds, which will differ on your hardware.
- **"Same result?"** compares the full output of the baseline and optimised versions byte for byte. Every optimisation changed speed only, never the answer.

**Key finding:** indexes alone fixed 5 of the 8 queries. Q2, Q5, Q6 and Q7 did not improve at all until the query itself was changed. In other words, adding an index is not enough if the query is written in a way that cannot use it.

## 5. Analysis of each query

### Q1: Patient history (184x faster, index)
- **Before:** `Parallel Seq Scan on encounter`. It read all 275,251 encounters to find this patient's 8, touching 14,862 buffers.
- **Cause:** PostgreSQL indexes primary keys and unique constraints automatically, but **not foreign keys**, so `encounter.patient_id` had no index. The drug subquery had the same problem with `prescription.encounter_id`.
- **Fix:** `idx_encounter_patient_started (patient_id, started_at DESC)`. It matches both the filter and the `ORDER BY`, so rows come out already sorted. Also added `idx_prescription_encounter`.
- **After:** index scans only, 140 buffers, about 0.6 ms.
- **Lesson:** index the foreign keys you join on.

### Q2: Doctor's daily schedule (43x faster, rewrite, no new index)
- **Before:** a sequential scan of all 300,000 appointments, which was surprising. The `no_doctor_double_booking` constraint from Portfolio 1 already builds a GiST index on `(doctor_id, slot)`.
- **Cause:** that index is **partial** (`WHERE status <> 'cancelled'`). The planner only uses a partial index when the query's WHERE clause guarantees the index's condition, and Q2 didn't.
- **Fix:** add `AND a.status <> 'cancelled'`. A doctor's schedule shouldn't show cancelled bookings anyway, and the result here was identical.
- **After:** `Bitmap Index Scan on no_doctor_double_booking`, 4 buffers.
- **Lesson:** the constraint index already did the work, so a new index would only have added write cost.

### Q3: Branch clinic list (32x faster, expression index)
- **Before:** `Parallel Seq Scan on appointment` with "Rows Removed by Filter: 99,950" in each of 3 workers. Together they discarded about 299,850 rows to keep 151.
- **Cause:** the query filters on `lower(slot)`, the start of the time range. An index on the column itself cannot answer a filter on a function of it.
- **Fix:** expression index `(branch_id, lower(slot))`. It is equality first, then range, which is the right column order for this pattern.

### Q4: Patient search by name (33x faster, expression index)
- **Before:** sequential scan of 60,000 patients, 59,848 removed by the filter.
- **Fix:** `(lower(last_name), lower(first_name) text_pattern_ops)`:
  - `lower()` makes the search case-insensitive, so "OKAFOR" and "Okafor" both match.
  - `text_pattern_ops` lets `LIKE 'chi%'` use the index whatever the database's collation.

### Q5: Cashier takings (19x faster, rewrite + index)
- **Before and after indexing:** both ~47-49 ms, still a sequential scan, even with `idx_payment_paid_at` in place.
- **Cause:** `WHERE paid_at::date = '2026-06-01'` converts *every row's* value before comparing, so the index on the raw `paid_at` column cannot be used. The predicate is not "sargable" (Search ARGument ABLE).
- **Fix:** rewrite as a half-open range: `paid_at >= '2026-06-01' AND paid_at < '2026-06-02'`. It is logically the same but can use the index.
- **After:** `Bitmap Index Scan on idx_payment_paid_at`, 303 buffers instead of 2,867.

### Q6: Monthly revenue report (706x faster, materialized view)
- **Cause:** this query legitimately needs a whole year of data: about 155,000 invoices and their line items. No index helps when most of a table must be read, and the optimiser correctly kept choosing sequential scans.
- **Fix:** a materialized view, `monthly_branch_revenue`, which stores the 69 pre-aggregated branch-month rows. The report reads those instead of 780,000 line items.
- **Trade-off:** the view is a snapshot. It must be refreshed, e.g. nightly with `REFRESH MATERIALIZED VIEW CONCURRENTLY monthly_branch_revenue`; the unique index makes `CONCURRENTLY` possible so reports are not blocked. That is acceptable for a management report but **not** for a cashier, who needs live figures.

### Q7: Patient's outstanding invoices (746x faster, rewrite + indexes)
- **Before:** 744 ms and **533,496 buffers** to return 2 rows. This is the most important finding of the portfolio.
- **Cause:** the `invoice_balance` view from Portfolio 1 joins invoices to *pre-grouped* subqueries (`GROUP BY invoice_id` over all of `invoice_item` and `payment`). PostgreSQL cannot push the `patient_id` filter inside a grouped subquery, so it totalled **all 287,251 invoices** and then threw away all but 8. Adding indexes changed almost nothing (671 ms).
- **Fix:** rewrite with `LATERAL` subqueries, which total only the invoices of this one patient. They use `idx_invoice_patient`, `idx_payment_invoice` and the existing `invoice_item` primary key.
- **After:** 87 buffers, 1.0 ms.
- **Lesson:** a view that is correct and convenient (Portfolio 1) can still perform badly for single-record lookups. A follow-up improvement would be to redefine `invoice_balance` with correlated subqueries, so every user of the view benefits.

### Q8: Urgent lab backlog (22x faster, partial index)
- **Cause:** only 1,304 of 165,173 lab requests (0.8%) are still waiting.
- **Fix:** a **partial** index `ON lab_request (requested_at) WHERE status = 'requested'`. It is **32 kB**, against 13 MB for the table, and stays small however many completed tests accumulate. It also returns rows already in `requested_at` order, so the `LIMIT 50` stops early.
- **Remaining work:** the plan still filters out 285 rows that are routine priority. Adding `priority` to the index would remove that, but at under 2 ms it is not worth it.
- **Note:** Q8 is slightly slower in the optimised phase than the indexed phase (1.83 vs 1.30 ms), even though the SQL is identical. That is normal measurement noise at sub-millisecond times.

## 6. Cost of the optimisations

Indexes are not free:
- **Space:** the 8 new indexes take about 29 MB in total (see `results/index_sizes.txt`).
- **Slower writes:** every INSERT or UPDATE must also update every index on that table. `payment` now maintains 4 indexes (2 of them new), so each new payment writes 4 index entries.

Design rules followed:
- Index only what a real, frequent query needs. No "index every column".
- Prefer **partial** indexes for small hot subsets (Q8), and **reuse** existing constraint indexes (Q2).
- Use **expression** indexes when the query filters on an expression (Q3, Q4).
- For reports that scan most of a table, pre-aggregate (Q6) instead of indexing.

## 7. Limitations

- The data is synthetic and evenly random in places where real data would cluster. For example, real hospitals have busy Monday mornings.
- All runs were warm-cache on one laptop. Cold-cache times, measured just after a server restart, would be higher for the baseline queries.
- Times are from a single concurrent user. Contention between many users is covered in Portfolio 3.

- Buffer counts quoted in section 5 come from `EXPLAIN (ANALYZE, BUFFERS)` and depend mostly on the data, which is identical on every machine because the generator uses a fixed random seed, so they should be very close on any computer. Check them against the files in `results/`.
