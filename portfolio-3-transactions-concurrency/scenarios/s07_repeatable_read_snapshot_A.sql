-- title: The same report under REPEATABLE READ (one snapshot for the whole transaction)
-- expect: both reads show 10,000; the new payment is only visible after COMMIT
-- session: Billing officer Lawal (end-of-day report)
-- start_after: 0
SET search_path TO hospital;
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT log('read 1: takings today = ' || sum(amount)) FROM payment
WHERE paid_at >= '2026-11-14 00:00+01' AND paid_at < '2026-11-15 00:00+01';
SELECT pg_sleep(1.5);
SELECT log('read 2: takings today = ' || sum(amount)) FROM payment
WHERE paid_at >= '2026-11-14 00:00+01' AND paid_at < '2026-11-15 00:00+01';
COMMIT;
SELECT log('COMMIT');
SELECT log('read 3 (new transaction): takings today = ' || sum(amount)) FROM payment
WHERE paid_at >= '2026-11-14 00:00+01' AND paid_at < '2026-11-15 00:00+01';
