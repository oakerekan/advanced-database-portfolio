-- title: Deadlock - two stock transfers between branches lock rows in opposite order
-- expect: PostgreSQL detects the deadlock and aborts one transfer; total stock stays 20
-- session: Pharmacist Musa (moves 2 Coartem Ikeja -> Lekki)
-- start_after: 0
SET search_path TO hospital;
BEGIN;
UPDATE branch_drug_stock SET quantity = quantity - 2 WHERE branch_id = 1 AND drug_id = 1;
SELECT log('locked Ikeja row (-2)');
SELECT pg_sleep(1);
SELECT log('now updating Lekki row (+2) ...');
UPDATE branch_drug_stock SET quantity = quantity + 2 WHERE branch_id = 2 AND drug_id = 1;
COMMIT;
SELECT log('transaction ended');
