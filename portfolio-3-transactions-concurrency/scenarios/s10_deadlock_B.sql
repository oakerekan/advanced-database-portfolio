-- session: Pharmacist Obi (moves 3 Coartem Lekki -> Ikeja)
-- start_after: 0.3
SET search_path TO hospital;
BEGIN;
UPDATE branch_drug_stock SET quantity = quantity - 3 WHERE branch_id = 2 AND drug_id = 1;
SELECT log('locked Lekki row (-3)');
SELECT pg_sleep(1);
SELECT log('now updating Ikeja row (+3) ...');
UPDATE branch_drug_stock SET quantity = quantity + 3 WHERE branch_id = 1 AND drug_id = 1;
COMMIT;
SELECT log('transaction ended');
