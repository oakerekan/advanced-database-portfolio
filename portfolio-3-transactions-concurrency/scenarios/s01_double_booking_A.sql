-- title: Two receptionists book overlapping slots for the same doctor at the same moment
-- expect: B waits for A, then is rejected by the exclusion constraint; one booking only
-- session: Receptionist Bakare
-- start_after: 0
SET search_path TO hospital;
BEGIN;
SELECT log('BEGIN; book Dr Okafor 10:00-10:30 for Chinedu');
INSERT INTO appointment (patient_id, doctor_id, branch_id, slot, booked_by)
VALUES (1, 1, 1, '[2026-12-01 10:00+01, 2026-12-01 10:30+01)', 3);
SELECT log('INSERT done, NOT committed; holding the transaction open for 2 s');
SELECT pg_sleep(2);
COMMIT;
SELECT log('COMMIT');
