-- session: Pharmacist Obi (moves 3 Coartem Lekki -> Ikeja)
-- start_after: 0.3
SET search_path TO hospital;
BEGIN;
SELECT log('lock both rows in branch_id order ...');
SELECT branch_id FROM branch_drug_stock WHERE drug_id = 1 AND branch_id IN (1, 2) ORDER BY branch_id FOR UPDATE;
SELECT log('both rows locked');
UPDATE branch_drug_stock SET quantity = quantity - 3 WHERE branch_id = 2 AND drug_id = 1;
SELECT log('updated Lekki row (-3)');
SELECT pg_sleep(1);
SELECT log('now updating Ikeja row (+3) ...');
UPDATE branch_drug_stock SET quantity = quantity + 3 WHERE branch_id = 1 AND drug_id = 1;
COMMIT;
SELECT log('COMMIT');
