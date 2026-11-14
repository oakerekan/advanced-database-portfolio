-- MIT 8103 - Portfolio 5: table on each shard. Run with -v branch=N
-- The CHECK makes each shard refuse rows that belong to another branch.
CREATE TABLE encounter_record (
    encounter_id   bigint        PRIMARY KEY,
    branch_id      smallint      NOT NULL CHECK (branch_id = :branch),
    hospital_no    varchar(15)   NOT NULL,
    started_at     timestamptz   NOT NULL,
    encounter_type varchar(12)   NOT NULL,
    primary_dx     varchar(8),
    amount         numeric(12,2) NOT NULL DEFAULT 0
);
CREATE INDEX ON encounter_record (hospital_no);
CREATE INDEX ON encounter_record (started_at);
