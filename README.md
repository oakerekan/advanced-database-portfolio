# Advanced Database Systems Portfolio (MIT 8103)

**Case study:** Lagoon Care Specialist Hospital, a simulated multi-branch private hospital in Lagos (Ikeja, Lekki, Yaba)
**DBMS:** PostgreSQL 16 (relational); NoSQL engine to be chosen in Portfolio 4

| Portfolio | Folder | Status |
|---|---|---|
| 1. Database Design and Modelling | [`portfolio-1-database-design`](portfolio-1-database-design/) | Complete |
| 2. Query Processing and Optimisation | `portfolio-2-query-optimisation` | Not started |
| 3. Transactions and Concurrency | `portfolio-3-transactions-concurrency` | Not started |
| 4. NoSQL and Advanced Data Models | `portfolio-4-nosql` | Not started |
| 5. Distributed and Cloud Database | `portfolio-5-distributed-cloud` | Not started |

## Quick start

```bash
createdb lagoon_care
psql -d lagoon_care -f portfolio-1-database-design/schema.sql
```
