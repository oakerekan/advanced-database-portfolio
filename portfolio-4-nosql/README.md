# Portfolio 4: NoSQL and Advanced Data Models

**Case study:** Laguna Care Specialist Hospital, using the same patients and visits as Portfolios 1–2
**Technologies:** MongoDB (document store), Redis (key-value store), PostgreSQL JSONB (document storage inside a relational database, used for comparison)

## 1. Why NoSQL for part of a hospital system?

The relational schema from Portfolio 1 is the right home for **billing, stock and bookings**. Those need strict constraints and multi-row ACID transactions (Portfolio 3). But two parts of the hospital fit tables badly:

1. **Clinical records are naturally documents, and their shape varies.**
   - A doctor reads a whole visit at once: complaint, vital signs, diagnoses, drugs and lab results. In the relational schema that takes joins across 8 tables (Portfolio 2, Q1).
   - Each lab test has different result fields. A malaria test has a result, a species and a parasite count; a full blood count has about 15 numbers; a genotype has one code. The relational model could only store a text `summary` (Portfolio 1, `lab_result`), and a column per possible field would mean hundreds of mostly-NULL columns.
   - Emergency visits record extra vital signs (oxygen saturation, Glasgow Coma Scale) that outpatient visits do not.
2. **Real-time operational data is short-lived, simple and very frequently updated.** Examples are the waiting queue, free beds, dashboards and notifications. It needs speed and atomic counters, not joins.

So this portfolio uses **two NoSQL models**:

| Need | Model | Technology |
|---|---|---|
| Patient records and clinical visits | **Document** | MongoDB (and PostgreSQL JSONB for comparison) |
| Clinic queue, bed availability, cache, dashboard, notifications | **Key-value** (with sorted sets, sets, hashes, streams) | Redis |

## 2. The document model

### Collections

**`patients`**: one document per patient, keyed by hospital number.
```json
{ "_id": "LCH-0000010", "name": {"first": "Kemi", "last": "Bello"}, "sex": "F",
  "dateOfBirth": "1999-05-04", "bloodGroup": "O+", "homeBranch": "IKJ",
  "contact": {"phone": "08010000010", "address": "118 Adeola Odeku Street, Lagos"},
  "insurance": {"provider": "NHIA (Formal Sector)", "type": "NHIA", "policyNo": "POL-00000010"},
  "allergies": ["Penicillin"] }
```
Optional fields such as `allergies`, `chronicConditions` and `insurance` appear only when they apply.

**`encounters`**: one **self-contained document per visit**, with everything recorded in it embedded. Full examples are in `sample_documents/`.
```json
{ "_id": "ENC-255848", "patientId": "LCH-0002946", "branch": "IKJ", "type": "emergency",
  "startedAt": "2026-08-30T13:23:31Z", "complaint": "Chest pain",
  "doctor": {"staffId": 130, "name": "Dr Funmilayo Ogunleye", "specialty": "Surgery"},
  "vitals": {"bp": {"systolic": 115, "diastolic": 81}, "tempC": 36.3, "pulse": 85, "spo2_pct": 97, "gcs": 10},
  "diagnoses": [{"code": "A09", "description": "Gastroenteritis", "primary": true}],
  "prescriptions": [{"drug": "Diclofenac", "strength": "1000 mg", "dose": "5 ml", "frequency": "once daily", "days": 30, "quantity": 60},
                    {"drug": "Vitamin C", "strength": "100 mg", "dose": "10 ml", "frequency": "12-hourly", "days": 30, "quantity": 60}],
  "labResults": [{"test": "FBC", "name": "Full Blood Count", "priority": "urgent", "status": "completed",
                  "resultAt": "2026-08-31T15:44:46Z", "abnormal": false,
                  "values": {"hb_g_dL": 13.4, "wbc_10e9_L": 9.5, "platelets_10e9_L": 198, "pcv_pct": 41}}] }
```

### Design decisions

| Decision | Choice | Reason |
|---|---|---|
| Diagnoses, prescriptions, vitals, lab results | **Embedded** in the encounter | Always read together with the visit, owned by it, and bounded in size (a visit has a handful of each). One read, no joins. |
| Encounters inside the patient document? | **No, a separate collection, referenced by `patientId`** | A patient's visits grow without limit over a lifetime. MongoDB documents are capped at 16 MB, and rewriting a large document on every visit would be slow. |
| Doctor details | **Copied** into each encounter (a snapshot) | The record must show who treated the patient *as they were then*, so a later name change should not alter history. This is deliberate denormalisation: no update is needed when staff details change. |
| Billing, stock, appointments | **Not moved** (they stay in PostgreSQL) | They need constraints across documents (no double booking, stock ≥ 0) and multi-row transactions. |
| Schema enforcement | `$jsonSchema` validator on required fields and enumerations only | Keeps the flexible parts flexible (lab `values`, optional patient fields) while rejecting broken records. |

### Data

`01_build_documents.sql` builds the documents from the Portfolio 2 relational data:
- **5,000 patients** and their **22,765 encounters**, about 19 MB of JSON.
- **30 lab-test types**, each with its own `values` shape. The values are synthetic, derived deterministically from the request ID, and consistent with the abnormal flag.

`02_export_for_mongodb.sql` writes the documents as JSON Lines for `mongoimport`.

## 3. Implementation and evidence

### 3a. MongoDB (`mongodb/`)

| Script | What it does |
|---|---|
| `01_prepare.js` | Converts ISO strings into BSON dates with an update pipeline, and adds `$jsonSchema` validators to both collections |
| `02_queries.js` | 8 operations (M1–M8). Each query's `explain("executionStats")` is printed **before and after** creating its index |
| `run_mongodb.sh` | `mongoimport` both collections, then runs the two scripts and saves `results/mongodb_output.txt` |

The operations:
- **M1. Patient history:** one `find` with no joins; compound index `{patientId: 1, startedAt: -1}`.
- **M2. Case-insensitive name search:** an index with a **collation** (`strength: 2`).
- **M3. Clinical alert, haemoglobin < 8 g/dL:** a query on a field that exists *only* in FBC results, using `$elemMatch` with a multikey index on `labResults.test` + `labResults.values.hb_g_dL`.
- **M4. Aggregation pipeline:** top 3 primary diagnoses per branch for 2025, using `$match`, `$unwind`, `$group`, `$sort`, `$group`/`$push` and `$slice`.
- **M5. `$lookup` safety check:** Penicillin-allergic patients who were prescribed Amoxicillin, which is itself a penicillin.
- **M6. Flexible schema:** counts documents with and without emergency-only vital signs.
- **M7. In-place updates:** `$push` a new lab result, and `$set` a brand-new field with no `ALTER TABLE`. Both are undone at the end.
- **M8. Validation:** inserts with `sex: "X"` and a non-existent branch are **rejected**.

**Expected results.** These are the numbers from the JSONB run below; your MongoDB run should match them:
- M1: 8 visits
- M2: 4 patients named Chinedu Okafor
- M3: 52 encounters
- M4: malaria first in every branch (IKJ 917, LKI 891, YAB 923)
- M5: 96 patients at risk
- M6: 1,710 encounters with GCS and 21,055 without; 30 test types

### 3b. The same model in PostgreSQL JSONB (`03_jsonb_document_store.sql`)

The **same documents** are stored as `jsonb` and queried with the same 8 operations, J1–J8. This ran successfully; see `results/jsonb_output.txt`.

| | Before index | After index |
|---|---|---|
| J1 patient history | Seq Scan, 22,757 rows removed by filter | Bitmap Index Scan on `enc_patient_history`, 8 rows |
| J3 Hb < 8 (JSON path `@?`) | Seq Scan, 22,713 rows removed by filter | Bitmap Index Scan on **GIN `jsonb_path_ops`** index, 767 candidates rechecked to 52 |

- **J4 aggregation:** `jsonb_array_elements` + `row_number()`, with the same results as M4.
- **J7 updates:** `jsonb_set` and the `||` operator.
- **J8 validation:** `CHECK` constraints on the JSON, which rejected both bad inserts.
- **Storage:** the GIN index on all encounter documents is 4.4 MB.

### 3c. Redis key-value store (`redis/hospital_realtime.redis`)

Output: `results/redis_output.txt`

| Use | Redis structure | Key commands | Why key-value fits |
|---|---|---|---|
| Live clinic queue | Sorted set (score = arrival time) | `ZADD`, `ZRANK`, `ZPOPMIN` | `ZPOPMIN` takes the next patient in one atomic step, so two doctors can't call the same person. |
| Free ICU beds | Set | `SADD`, `SPOP`, `SCARD` | `SPOP` allocates a bed atomically. This is the same guarantee as Portfolio 3's locking, without a transaction. |
| Patient summary cache | String with expiry | `SET ... EX 300`, `TTL` | Takes repeated reads off PostgreSQL; the entry expires automatically. |
| Daily dashboard | Hash + atomic increment | `HINCRBY`, `HINCRBYFLOAT` | Counters update without read-then-write, so there's no lost update (Portfolio 3, s03). |
| Doctor status board | Hash | `HSET`, `HGETALL` | One small record per doctor, overwritten constantly. |
| Lab result notifications | Stream | `XADD`, `XRANGE` | Wards read new results in order, as they arrive. |

`SPOP` picks a random member, so which ICU bed is allocated can differ between runs.

## 4. Relational vs document vs key-value: evaluation

| Criterion | PostgreSQL (relational) | MongoDB (document) | Redis (key-value) |
|---|---|---|---|
| Reading one whole visit | Joins across 8 tables | 1 document read | n/a |
| Variable lab-result fields | Text summary only, or many NULL columns | Natural: each result has its own `values` | n/a |
| Adding a new field | `ALTER TABLE` | Just write it (M7) | Just write it |
| Integrity across records (no double booking, stock ≥ 0) | Strong: constraints, FKs, ACID (Portfolios 1 and 3) | Weak: per-document atomicity by default; multi-document transactions exist but cost more | Per-command atomicity only |
| Ad-hoc reporting across everything | Strong (SQL, joins) | Good (aggregation pipeline, `$lookup`) | Poor |
| Speed for tiny, hot data | Good | Good | Excellent: in memory |
| Durability | Strong (WAL) | Strong (journal, replica sets) | Configurable. Data is lost on restart unless persistence is enabled, so it is used only for data that can be rebuilt. |

**Recommended architecture (polyglot persistence):**
- **PostgreSQL** remains the system of record for patients, bookings, stock and billing.
- **MongoDB** holds the clinical record documents. In production they would be written by the clinical application, or streamed from PostgreSQL with change-data-capture.
- **Redis** holds the live queue, bed board, caches and notifications. All of that can be rebuilt from PostgreSQL if Redis restarts.

**Trade-offs accepted:**
- *Duplication:* doctor names live in every encounter.
- *Eventual consistency:* the record documents and the relational tables may disagree for a moment if synchronised asynchronously.
- *Two more systems to run, back up and secure.* For patient data, that includes access control and encryption under the NDPA (Nigeria Data Protection Act).

**PostgreSQL JSONB as an alternative.** The JSONB results show that one database *can* provide document storage with GIN indexes, keeping ACID and joins to the relational tables. For a hospital group of this size, that is a credible simpler option. MongoDB's advantages appear at larger scale: built-in sharding and replica sets (Portfolio 5), plus a query language designed for nested data.

## 5. How to run

```bash
# 1. PostgreSQL parts (needs the Portfolio 2 database with data)
./run_postgres.sh                 # builds documents, exports data/*.json, runs JSONB queries

# 2. MongoDB (needs MongoDB 5.0+, mongosh and mongoimport on PATH)
./mongodb/run_mongodb.sh          # or: export MONGO_URI="mongodb+srv://..." for MongoDB Atlas

# 3. Redis (needs a Redis server; on Windows use Memurai, WSL or Redis Cloud)
./redis/run_redis.sh
```

`data/` (about 18 MB) is generated, so it is git-ignored. Run `run_postgres.sh` to recreate it.
