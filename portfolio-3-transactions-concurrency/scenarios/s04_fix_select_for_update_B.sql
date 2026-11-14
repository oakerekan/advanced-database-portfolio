-- session: Pharmacist Obi (dispenses 4 Coartem)
-- start_after: 0.5
SET search_path TO hospital;
BEGIN;
SELECT log('SELECT ... FOR UPDATE (waits if the row is locked)');
SELECT quantity AS q FROM branch_drug_stock WHERE branch_id = 1 AND drug_id = 1 FOR UPDATE \gset
SELECT log('read Coartem stock = ' || :q || '; will dispense 4');
SELECT pg_sleep(1.5);
UPDATE branch_drug_stock SET quantity = :q - 4 WHERE branch_id = 1 AND drug_id = 1;
SELECT log('UPDATE stock = ' || (:q - 4));
COMMIT;
SELECT log('COMMIT');
