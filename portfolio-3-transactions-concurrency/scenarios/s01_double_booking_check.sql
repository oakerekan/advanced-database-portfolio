SET search_path TO hospital;
SELECT a.appointment_id, p.first_name AS patient, lower(a.slot) AS starts, upper(a.slot) AS ends
FROM appointment a JOIN patient p USING (patient_id) ORDER BY a.appointment_id;
SELECT CASE WHEN count(*) = 1 THEN 'RESULT: 1 booking saved - double booking prevented'
            ELSE 'RESULT: ' || count(*) || ' bookings saved - DOUBLE BOOKED' END AS verdict
FROM appointment WHERE doctor_id = 1;
