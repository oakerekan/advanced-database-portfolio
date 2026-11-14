-- MIT 8103 - Portfolio 5: 30,000 encounters inserted through the coordinator.
-- Same distribution as Portfolio 2: about half at Ikeja, 30% Lekki, 20% Yaba.
SELECT setseed(0.5) \gset
INSERT INTO encounter_record
SELECT i,
       CASE WHEN r < 0.5 THEN 1 WHEN r < 0.8 THEN 2 ELSE 3 END,
       'LCH-' || lpad((1 + (i * 7919) % 60000)::text, 7, '0'),
       TIMESTAMPTZ '2025-01-01' + (i % 680) * INTERVAL '1 day' + (i % 9) * INTERVAL '1 hour',
       CASE WHEN i % 13 = 0 THEN 'emergency' ELSE 'outpatient' END,
       (ARRAY['B54','I10','A01.0','E11.9','J06.9','N39.0','K29.7','J18.9'])[1 + i % 8],
       round((10000 + random() * 90000)::numeric, 2)
FROM (SELECT i, random() AS r FROM generate_series(1, 30000) i) g;
-- make sure one known patient has visits at several branches
INSERT INTO encounter_record VALUES
 (30001, 1, 'LCH-0000013', '2025-02-04 10:00+01', 'outpatient', 'B54', 18500),
 (30002, 2, 'LCH-0000013', '2025-10-10 11:00+01', 'outpatient', 'H66.9', 12000),
 (30003, 3, 'LCH-0000013', '2026-08-12 09:30+01', 'outpatient', 'B54', 21000);
