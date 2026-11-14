-- session: Pharmacist Obi (dispenses 4 Coartem, retries on conflict)
-- start_after: 0.5
SET search_path TO hospital;
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT quantity AS q FROM branch_drug_stock WHERE branch_id = 1 AND drug_id = 1 \gset
SELECT log('attempt 1: read Coartem stock = ' || :q || '; will dispense 4');
SELECT pg_sleep(1.5);
UPDATE branch_drug_stock SET quantity = :q - 4 WHERE branch_id = 1 AND drug_id = 1;
\set update_failed :ERROR
COMMIT;
\if :update_failed
  SELECT log('attempt 1 rolled back (SQLSTATE 40001) -> retrying in a new transaction');
  BEGIN ISOLATION LEVEL REPEATABLE READ;
  SELECT quantity AS q FROM branch_drug_stock WHERE branch_id = 1 AND drug_id = 1 \gset
  SELECT log('attempt 2: read Coartem stock = ' || :q || '; will dispense 4');
  UPDATE branch_drug_stock SET quantity = :q - 4 WHERE branch_id = 1 AND drug_id = 1;
  SELECT log('UPDATE stock = ' || (:q - 4));
  COMMIT;
  SELECT log('COMMIT');
\endif
