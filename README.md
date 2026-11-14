# Advanced Database Systems Portfolio (MIT 8103)

**Student:** Olayinka Gaius Akerekan, 301912616, Master of Information Technology, 2026/2027 first semester

**Case study:** Laguna Care Specialist Hospital, a simulated multi-branch private hospital in Lagos (Ikeja, Lekki, Yaba)
**DBMS:** PostgreSQL 15 (relational), MongoDB and Redis (NoSQL)

| Portfolio | Folder | Status |
|---|---|---|
| 1. Database Design and Modelling | [`portfolio-1-database-design`](portfolio-1-database-design/) | Complete |
| 2. Query Processing and Optimisation | [`portfolio-2-query-optimisation`](portfolio-2-query-optimisation/) | Complete |
| 3. Transactions and Concurrency | [`portfolio-3-transactions-concurrency`](portfolio-3-transactions-concurrency/) | Complete |
| 4. NoSQL and Advanced Data Models | [`portfolio-4-nosql`](portfolio-4-nosql/) | Complete |
| 5. Distributed and Cloud Database | [`portfolio-5-distributed-cloud`](portfolio-5-distributed-cloud/) | Complete |

## Repository structure

```
advanced-database-portfolio/
├── portfolio-1-database-design/          schema.sql, constraint tests, ER diagram, README
├── portfolio-2-query-optimisation/       data generator, queries, indexes, benchmark, plans
├── portfolio-3-transactions-concurrency/ transaction scripts, 11 two-session scenarios
├── portfolio-4-nosql/                    MongoDB, PostgreSQL JSONB and Redis models
├── portfolio-5-distributed-cloud/        replication/failover and sharding cluster scripts
├── docs/                                 final documentation and GitHub evidence
└── README.md
```

Each portfolio folder has its own `README.md` (what was done and why), a `results/` folder (raw output from running the scripts) and a `screenshots/` folder (evidence from my local runs on PostgreSQL 15, MongoDB 9.0 and Windows).

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

## AI use declaration

- **Tool used:** Claude (Anthropic), via claude.ai.
- **What it was used for:** generating the synthetic dataset; writing the SQL, Python, JavaScript and shell scripts and the README files; designing the ER diagram and database schema; drafting the summary documentation; and helping troubleshoot my PostgreSQL and MongoDB setup.
- **How I reviewed and verified the output:**
    - I ran all five portfolios on my own laptop (PostgreSQL 15.14 and MongoDB 9.0 on Windows) and checked every result against its expected outcome.
    - I replaced the reference timings in Portfolio 2 with my own.
    - A difference found while running the MongoDB part (`distinct()` counting a missing field as `null`) was investigated and fixed.
    - The screenshots in each `screenshots/` folder come from my own runs.

## References

1. PostgreSQL Global Development Group. *PostgreSQL 15 Documentation*. https://www.postgresql.org/docs/15/
2. MongoDB Inc. *MongoDB Manual*. https://www.mongodb.com/docs/manual/
3. Redis Ltd. *Redis documentation*. https://redis.io/docs/
4. Elmasri, R. and Navathe, S. B. (2016). *Fundamentals of Database Systems*, 7th ed. Pearson.
5. Kleppmann, M. (2017). *Designing Data-Intensive Applications*. O'Reilly.
6. Ports, D. R. K. and Grittner, K. (2012). Serializable Snapshot Isolation in PostgreSQL. *Proceedings of the VLDB Endowment*, 5(12).
7. Federal Republic of Nigeria (2023). *Nigeria Data Protection Act, 2023*.
