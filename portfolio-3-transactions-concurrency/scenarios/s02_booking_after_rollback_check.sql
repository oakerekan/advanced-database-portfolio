SET search_path TO hospital;
SELECT a.appointment_id, p.first_name AS patient, lower(a.slot) AS starts, upper(a.slot) AS ends
FROM appointment a JOIN patient p USING (patient_id) ORDER BY a.appointment_id;
SELECT CASE WHEN count(*) = 1 AND bool_and(patient_id = 2) THEN 'RESULT: Ngozi''s booking saved after A rolled back'
            ELSE 'RESULT: unexpected - ' || count(*) || ' bookings' END AS verdict
FROM appointment;
