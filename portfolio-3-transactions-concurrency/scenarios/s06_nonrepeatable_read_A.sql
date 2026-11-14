-- title: Non-repeatable read - a report reads the same total twice in READ COMMITTED
-- expect: the two reads inside ONE transaction disagree (10,000 then 30,000)
-- session: Billing officer Lawal (end-of-day report)
-- start_after: 0
SET search_path TO hospital;
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT log('read 1: takings today = ' || sum(amount)) FROM payment
WHERE paid_at >= '2026-11-14 00:00+01' AND paid_at < '2026-11-15 00:00+01';
SELECT pg_sleep(1.5);
SELECT log('read 2: takings today = ' || sum(amount)) FROM payment
WHERE paid_at >= '2026-11-14 00:00+01' AND paid_at < '2026-11-15 00:00+01';
COMMIT;
SELECT log('COMMIT');
