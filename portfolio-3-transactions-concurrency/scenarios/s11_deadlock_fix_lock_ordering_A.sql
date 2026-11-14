-- title: Deadlock fix - every transfer locks rows in the same order (lowest branch_id first)
-- expect: B simply waits for A; both transfers succeed; Ikeja 11, Lekki 9, total 20
-- session: Pharmacist Musa (moves 2 Coartem Ikeja -> Lekki)
-- start_after: 0
SET search_path TO hospital;
BEGIN;
SELECT log('lock both rows in branch_id order ...');
SELECT branch_id FROM branch_drug_stock WHERE drug_id = 1 AND branch_id IN (1, 2) ORDER BY branch_id FOR UPDATE;
SELECT log('both rows locked');
UPDATE branch_drug_stock SET quantity = quantity - 2 WHERE branch_id = 1 AND drug_id = 1;
SELECT log('updated Ikeja row (-2)');
SELECT pg_sleep(1);
SELECT log('now updating Lekki row (+2) ...');
UPDATE branch_drug_stock SET quantity = quantity + 2 WHERE branch_id = 2 AND drug_id = 1;
COMMIT;
SELECT log('COMMIT');
