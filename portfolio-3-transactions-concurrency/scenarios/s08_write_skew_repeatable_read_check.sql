SET search_path TO hospital;
SELECT bed_label, is_in_service FROM bed WHERE ward_id = 1 ORDER BY bed_id;
SELECT CASE WHEN count(*) FILTER (WHERE is_in_service) >= 1
            THEN 'RESULT: ' || count(*) FILTER (WHERE is_in_service) || ' ICU bed(s) in service - rule kept'
            ELSE 'RESULT: 0 ICU beds in service - WRITE SKEW broke the rule' END AS verdict
FROM bed WHERE ward_id = 1;
