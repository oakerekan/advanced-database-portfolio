-- session: Receptionist Eze
-- start_after: 0.5
SET search_path TO hospital;
BEGIN;
SELECT log('BEGIN; book Dr Okafor 10:15-10:45 for Ngozi (overlaps A) ... waiting?');
INSERT INTO appointment (patient_id, doctor_id, branch_id, slot, booked_by)
VALUES (2, 1, 1, '[2026-12-01 10:15+01, 2026-12-01 10:45+01)', 4);
SELECT log('INSERT succeeded once A rolled back');
COMMIT;
SELECT log('COMMIT');
