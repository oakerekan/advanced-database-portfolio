# Advanced Database Systems Portfolio (MIT 8103)

**Case study:** Laguna Care Specialist Hospital, a simulated multi-branch private hospital in Lagos (Ikeja, Lekki, Yaba)
**DBMS:** PostgreSQL 15 (relational), MongoDB and Redis (NoSQL)

| Portfolio | Folder | Status |
|---|---|---|
| 1. Database Design and Modelling | [`portfolio-1-database-design`](portfolio-1-database-design/) | Complete |
| 2. Query Processing and Optimisation | [`portfolio-2-query-optimisation`](portfolio-2-query-optimisation/) | Complete |
| 3. Transactions and Concurrency | [`portfolio-3-transactions-concurrency`](portfolio-3-transactions-concurrency/) | Complete |
| 4. NoSQL and Advanced Data Models | [`portfolio-4-nosql`](portfolio-4-nosql/) | Complete (run MongoDB part locally) |
| 5. Distributed and Cloud Database | [`portfolio-5-distributed-cloud`](portfolio-5-distributed-cloud/) | Complete |

## How to run everything

Requirements:
- PostgreSQL 15+ with `psql`, `createdb`, `initdb`, `pg_ctl` and `pg_basebackup` on `PATH`
- Python 3
- Git Bash on Windows
- For Portfolio 4: MongoDB 5.0+ with `mongosh` and `mongoimport`, and optionally Redis

```bash
export PGHOST=localhost PGUSER=postgres PGPASSWORD='your password'

# Portfolio 1: schema + constraint tests
createdb laguna_care
psql -d laguna_care -f portfolio-1-database-design/schema.sql
psql -d laguna_care -f portfolio-1-database-design/constraint_tests.sql > portfolio-1-database-design/constraint_tests_output.txt 2>&1

./portfolio-2-query-optimisation/run_all.sh        # 3.3M rows + benchmark (3-10 min)
./portfolio-3-transactions-concurrency/run_all.sh  # transactions + 11 concurrency scenarios (~30 s)
./portfolio-4-nosql/run_postgres.sh                # documents, JSON export, JSONB queries (needs Portfolio 2 data)
./portfolio-4-nosql/mongodb/run_mongodb.sh         # MongoDB
./portfolio-4-nosql/redis/run_redis.sh             # Redis (optional)
./portfolio-5-distributed-cloud/01_replication.sh  # primary + 2 standbys, failover (ports 5433-5435)
./portfolio-5-distributed-cloud/02_sharding.sh     # coordinator + 3 shards (ports 5440-5443)
./portfolio-5-distributed-cloud/03_stop_all.sh     # stop the Portfolio 5 servers
```

All data is synthetic. No real patient information is used.
