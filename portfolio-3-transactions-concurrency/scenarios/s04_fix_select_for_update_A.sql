-- title: Fix 1 - pessimistic locking with SELECT ... FOR UPDATE (READ COMMITTED)
-- expect: B blocks on its read until A commits, then reads 7 and writes 3
-- session: Pharmacist Musa (dispenses 3 Coartem)
-- start_after: 0
SET search_path TO hospital;
BEGIN;
SELECT quantity AS q FROM branch_drug_stock WHERE branch_id = 1 AND drug_id = 1 FOR UPDATE \gset
SELECT log('read Coartem stock = ' || :q || '; will dispense 3');
SELECT pg_sleep(1.5);
UPDATE branch_drug_stock SET quantity = :q - 3 WHERE branch_id = 1 AND drug_id = 1;
SELECT log('UPDATE stock = ' || (:q - 3));
COMMIT;
SELECT log('COMMIT');
