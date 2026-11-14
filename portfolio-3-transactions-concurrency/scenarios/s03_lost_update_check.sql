SET search_path TO hospital;
SELECT quantity AS ikeja_coartem_stock, 10 - 3 - 4 AS correct_value
FROM branch_drug_stock WHERE branch_id = 1 AND drug_id = 1;
SELECT CASE WHEN quantity = 3 THEN 'RESULT: stock = 3, correct'
            ELSE 'RESULT: stock = ' || quantity || ', should be 3 - LOST UPDATE (7 dispensed, only 4 deducted)' END AS verdict
FROM branch_drug_stock WHERE branch_id = 1 AND drug_id = 1;
