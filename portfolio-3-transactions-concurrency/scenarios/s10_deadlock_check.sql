SET search_path TO hospital;
SELECT b.branch_code, s.quantity FROM branch_drug_stock s JOIN branch b USING (branch_id) WHERE drug_id = 1 ORDER BY branch_id;
SELECT 'RESULT: Ikeja ' || max(quantity) FILTER (WHERE branch_id = 1) || ', Lekki ' || max(quantity) FILTER (WHERE branch_id = 2)
       || ', total ' || sum(quantity) || CASE WHEN sum(quantity) = 20 THEN ' (consistent)' ELSE ' (INCONSISTENT)' END
       || ' - only one transfer applied' AS verdict
FROM branch_drug_stock WHERE drug_id = 1;
