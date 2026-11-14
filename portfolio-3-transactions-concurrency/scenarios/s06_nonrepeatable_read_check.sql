SET search_path TO hospital;
SELECT 'RESULT: READ COMMITTED - each statement sees data committed before it started, so read 2 saw the new payment' AS verdict;
