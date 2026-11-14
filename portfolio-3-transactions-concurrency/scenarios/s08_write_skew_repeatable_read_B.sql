-- session: Nurse B (takes ICU-02 out for repair)
-- start_after: 0.3
SET search_path TO hospital;
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT count(*) AS n FROM bed WHERE ward_id = 1 AND is_in_service \gset
SELECT log('ICU beds in service = ' || :n);
SELECT :n >= 2 AS ok \gset
SELECT pg_sleep(1);
\if :ok
  UPDATE bed SET is_in_service = FALSE WHERE bed_id = 2;
  SELECT log('rule OK (>= 2) -> ICU-02 taken out of service');
\else
  SELECT log('refused: ICU-02 is needed (last bed in service)');
\endif
COMMIT;
SELECT log('COMMIT');
