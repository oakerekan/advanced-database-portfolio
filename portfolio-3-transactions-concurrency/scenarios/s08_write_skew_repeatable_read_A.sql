-- title: Write skew - rule "ICU keeps at least 1 bed in service", two nurses, REPEATABLE READ
-- expect: both see 2 beds, both take one out -> 0 ICU beds in service (rule broken)
-- session: Nurse A (takes ICU-01 out for cleaning)
-- start_after: 0
SET search_path TO hospital;
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT count(*) AS n FROM bed WHERE ward_id = 1 AND is_in_service \gset
SELECT log('ICU beds in service = ' || :n);
SELECT :n >= 2 AS ok \gset
SELECT pg_sleep(1);
\if :ok
  UPDATE bed SET is_in_service = FALSE WHERE bed_id = 1;
  SELECT log('rule OK (>= 2) -> ICU-01 taken out of service');
\else
  SELECT log('refused: ICU-01 is needed (last bed in service)');
\endif
COMMIT;
SELECT log('COMMIT');
