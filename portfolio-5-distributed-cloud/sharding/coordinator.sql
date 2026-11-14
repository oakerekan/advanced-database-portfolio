-- MIT 8103 - Portfolio 5: coordinator node
CREATE EXTENSION postgres_fdw;

-- one foreign server per shard; async_capable lets the coordinator query shards in parallel
CREATE SERVER shard_ikj FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'localhost', port '5441', dbname 'laguna_shard', async_capable 'true', batch_size '1000');
CREATE SERVER shard_lki FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'localhost', port '5442', dbname 'laguna_shard', async_capable 'true', batch_size '1000');
CREATE SERVER shard_yab FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'localhost', port '5443', dbname 'laguna_shard', async_capable 'true', batch_size '1000');
CREATE USER MAPPING FOR CURRENT_USER SERVER shard_ikj OPTIONS (user 'postgres');
CREATE USER MAPPING FOR CURRENT_USER SERVER shard_lki OPTIONS (user 'postgres');
CREATE USER MAPPING FOR CURRENT_USER SERVER shard_yab OPTIONS (user 'postgres');

-- the sharded table: shard key = branch_id
CREATE TABLE encounter_record (
    encounter_id   bigint        NOT NULL,
    branch_id      smallint      NOT NULL,
    hospital_no    varchar(15)   NOT NULL,
    started_at     timestamptz   NOT NULL,
    encounter_type varchar(12)   NOT NULL,
    primary_dx     varchar(8),
    amount         numeric(12,2) NOT NULL DEFAULT 0
) PARTITION BY LIST (branch_id);

CREATE FOREIGN TABLE encounter_ikj PARTITION OF encounter_record FOR VALUES IN (1)
    SERVER shard_ikj OPTIONS (table_name 'encounter_record');
CREATE FOREIGN TABLE encounter_lki PARTITION OF encounter_record FOR VALUES IN (2)
    SERVER shard_lki OPTIONS (table_name 'encounter_record');
CREATE FOREIGN TABLE encounter_yab PARTITION OF encounter_record FOR VALUES IN (3)
    SERVER shard_yab OPTIONS (table_name 'encounter_record');

-- small reference table kept on the coordinator (in production: replicated to every shard)
CREATE TABLE branch (branch_id smallint PRIMARY KEY, branch_code char(3) NOT NULL, name text NOT NULL);
INSERT INTO branch VALUES (1,'IKJ','Laguna Care Ikeja'), (2,'LKI','Laguna Care Lekki'), (3,'YAB','Laguna Care Yaba');
