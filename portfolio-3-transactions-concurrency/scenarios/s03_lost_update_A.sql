-- title: Lost update - two pharmacists read stock, then write back (read-then-write, READ COMMITTED)
-- expect: stock should end at 10 - 3 - 4 = 3, but ends at 6: A's update is lost
-- session: Pharmacist Musa (dispenses 3 Coartem)
-- start_after: 0
SET search_path TO hospital;
BEGIN;
SELECT quantity AS q FROM branch_drug_stock WHERE branch_id = 1 AND drug_id = 1 \gset
SELECT log('read Coartem stock = ' || :q || '; will dispense 3');
SELECT pg_sleep(1.5);
UPDATE branch_drug_stock SET quantity = :q - 3 WHERE branch_id = 1 AND drug_id = 1;
SELECT log('UPDATE stock = ' || (:q - 3));
COMMIT;
SELECT log('COMMIT');
