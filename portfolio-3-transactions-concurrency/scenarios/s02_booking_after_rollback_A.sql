-- title: As s01, but the first receptionist rolls back (patient changes their mind)
-- expect: B waits for A; once A rolls back, B's booking succeeds
-- session: Receptionist Bakare
-- start_after: 0
SET search_path TO hospital;
BEGIN;
SELECT log('BEGIN; book Dr Okafor 10:00-10:30 for Chinedu');
INSERT INTO appointment (patient_id, doctor_id, branch_id, slot, booked_by)
VALUES (1, 1, 1, '[2026-12-01 10:00+01, 2026-12-01 10:30+01)', 3);
SELECT log('INSERT done, NOT committed; patient is deciding...');
SELECT pg_sleep(2);
ROLLBACK;
SELECT log('ROLLBACK (patient cancelled)');
