SET search_path TO hospital;
SELECT b.branch_code, s.quantity FROM branch_drug_stock s JOIN branch b USING (branch_id) WHERE drug_id = 1 ORDER BY branch_id;
SELECT CASE WHEN max(quantity) FILTER (WHERE branch_id = 1) = 11 AND max(quantity) FILTER (WHERE branch_id = 2) = 9
            THEN 'RESULT: Ikeja 11, Lekki 9, total 20 - both transfers applied, no deadlock'
            ELSE 'RESULT: unexpected stock values' END AS verdict
FROM branch_drug_stock WHERE drug_id = 1;
