-- =====================================================================
-- MIT 8103 - Portfolio 4: the SAME document model in PostgreSQL JSONB
-- Mirrors mongodb/02_queries.js (M1-M8) so the results can be compared.
-- Run: psql -d laguna_care -f 03_jsonb_document_store.sql
-- =====================================================================
SET search_path TO docstore;
\pset footer off
DROP INDEX IF EXISTS enc_patient_history, enc_doc_gin, pat_name_ci;
ALTER TABLE encounters DROP CONSTRAINT IF EXISTS enc_valid;
ALTER TABLE patients   DROP CONSTRAINT IF EXISTS pat_valid;

\echo '=== J1 (= M1). Patient history for LCH-0000013, newest first ==='
\echo '--- before index'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT doc FROM encounters WHERE doc->>'patientId' = 'LCH-0000013' ORDER BY doc->>'startedAt' DESC;
CREATE INDEX enc_patient_history ON encounters ((doc->>'patientId'), (doc->>'startedAt') DESC);
ANALYZE encounters;
\echo '--- after index'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT doc FROM encounters WHERE doc->>'patientId' = 'LCH-0000013' ORDER BY doc->>'startedAt' DESC;
SELECT left(doc->>'startedAt', 10) AS visit, doc->>'branch' AS br, doc#>>'{doctor,name}' AS doctor,
       (SELECT d->>'code' || ' ' || (d->>'description') FROM jsonb_array_elements(doc->'diagnoses') d
         WHERE (d->>'primary')::boolean) AS primary_diagnosis,
       (SELECT string_agg(p->>'drug', ', ') FROM jsonb_array_elements(doc->'prescriptions') p) AS drugs,
       (SELECT string_agg(l->>'test', ', ') FROM jsonb_array_elements(doc->'labResults') l) AS labs
FROM encounters WHERE doc->>'patientId' = 'LCH-0000013' ORDER BY doc->>'startedAt' DESC;

\echo '=== J2 (= M2). Case-insensitive name search ==='
CREATE INDEX pat_name_ci ON patients (lower(doc#>>'{name,last}'), lower(doc#>>'{name,first}'));
ANALYZE patients;
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT id FROM patients WHERE lower(doc#>>'{name,last}') = lower('OKAFOR') AND lower(doc#>>'{name,first}') = lower('chinedu');
SELECT id, doc#>>'{name,first}' AS first, doc#>>'{name,last}' AS last, doc->>'dateOfBirth' AS born
FROM patients WHERE lower(doc#>>'{name,last}') = lower('OKAFOR') AND lower(doc#>>'{name,first}') = lower('chinedu')
ORDER BY id;

\echo '=== J3 (= M3). FBC results with haemoglobin below 8 g/dL (JSON path query) ==='
\echo '--- before index'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT id FROM encounters WHERE doc @? '$.labResults[*] ? (@.test == "FBC" && @.values.hb_g_dL < 8)';
CREATE INDEX enc_doc_gin ON encounters USING gin (doc jsonb_path_ops);
ANALYZE encounters;
\echo '--- after GIN index'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT id FROM encounters WHERE doc @? '$.labResults[*] ? (@.test == "FBC" && @.values.hb_g_dL < 8)';
SELECT count(*) AS matching_encounters
FROM encounters WHERE doc @? '$.labResults[*] ? (@.test == "FBC" && @.values.hb_g_dL < 8)';
SELECT doc->>'patientId' AS patient, left(doc->>'startedAt', 10) AS visit, doc->>'branch' AS br,
       jsonb_path_query_first(doc, '$.labResults[*] ? (@.test == "FBC").values.hb_g_dL') AS hb
FROM encounters WHERE doc @? '$.labResults[*] ? (@.test == "FBC" && @.values.hb_g_dL < 8)'
ORDER BY doc->>'startedAt' DESC LIMIT 5;

\echo '=== J4 (= M4). Top 3 primary diagnoses per branch in 2025 ==='
WITH d AS (
  SELECT e.doc->>'branch' AS branch, x->>'code' AS code, x->>'description' AS description, count(*) AS visits
  FROM encounters e, jsonb_array_elements(e.doc->'diagnoses') x
  WHERE e.doc->>'startedAt' >= '2025-01-01' AND e.doc->>'startedAt' < '2026-01-01'
    AND (x->>'primary')::boolean
  GROUP BY 1, 2, 3
), r AS (
  SELECT *, row_number() OVER (PARTITION BY branch ORDER BY visits DESC, code) AS rn FROM d
)
SELECT branch, string_agg(code || ' ' || description || ' (' || visits || ')', '; ' ORDER BY rn) AS top3
FROM r WHERE rn <= 3 GROUP BY branch ORDER BY branch;

\echo '=== J5 (= M5). Patients allergic to Penicillin who were prescribed Amoxicillin ==='
SELECT count(*) AS patients_at_risk FROM (
  SELECT p.id FROM patients p
  JOIN encounters e ON e.doc->>'patientId' = p.id
  WHERE p.doc @> '{"allergies":["Penicillin"]}' AND e.doc @> '{"prescriptions":[{"drug":"Amoxicillin"}]}'
  GROUP BY p.id) s;
SELECT p.id, (p.doc#>>'{name,first}') || ' ' || (p.doc#>>'{name,last}') AS name, count(*) AS amoxicillin_visits
FROM patients p JOIN encounters e ON e.doc->>'patientId' = p.id
WHERE p.doc @> '{"allergies":["Penicillin"]}' AND e.doc @> '{"prescriptions":[{"drug":"Amoxicillin"}]}'
GROUP BY p.id, name ORDER BY amoxicillin_visits DESC, p.id LIMIT 5;

\echo '=== J6 (= M6). Flexible schema ==='
SELECT count(*) FILTER (WHERE doc->'vitals' ? 'gcs')     AS with_gcs,
       count(*) FILTER (WHERE NOT doc->'vitals' ? 'gcs') AS without_gcs,
       (SELECT count(DISTINCT l->>'test') FROM encounters, jsonb_array_elements(doc->'labResults') l) AS distinct_lab_tests
FROM encounters;

\echo '=== J7 (= M7). Update inside a document, in a transaction that is rolled back ==='
BEGIN;
UPDATE encounters SET doc = jsonb_set(doc, '{labResults}', COALESCE(doc->'labResults', '[]') ||
  '[{"test":"MP","name":"Malaria Parasite","status":"completed","abnormal":true,"values":{"result":"positive","parasitesPerUL":12000}}]')
WHERE id = (SELECT id FROM encounters WHERE doc->>'patientId' = 'LCH-0000013' ORDER BY doc->>'startedAt' DESC LIMIT 1);
UPDATE patients SET doc = doc || '{"emergencyContact":{"name":"Mr Akinola","relationship":"spouse"}}' WHERE id = 'LCH-0000013';
SELECT doc->'emergencyContact' AS new_field FROM patients WHERE id = 'LCH-0000013';
ROLLBACK;

\echo '=== J8 (= M8). Validation with CHECK constraints on JSON ==='
ALTER TABLE patients ADD CONSTRAINT pat_valid CHECK (
  doc ?& ARRAY['name','dateOfBirth','sex','homeBranch','contact']
  AND doc->>'sex' IN ('M','F') AND doc->>'homeBranch' IN ('IKJ','LKI','YAB'));
ALTER TABLE encounters ADD CONSTRAINT enc_valid CHECK (
  doc ?& ARRAY['patientId','branch','type','startedAt','doctor']
  AND doc->>'branch' IN ('IKJ','LKI','YAB')
  AND doc->>'type' IN ('outpatient','emergency','inpatient','follow_up'));
INSERT INTO patients VALUES ('LCH-9999999',
  '{"_id":"LCH-9999999","name":{"first":"Test","last":"Patient"},"dateOfBirth":"2000-01-01","sex":"X","homeBranch":"IKJ","contact":{}}');
INSERT INTO encounters VALUES ('ENC-X',
  '{"_id":"ENC-X","patientId":"LCH-0000013","branch":"ABJ","type":"outpatient","startedAt":"2026-11-14T09:00:00Z","doctor":{"staffId":1}}');

\echo '=== Storage ==='
SELECT 'encounters' AS collection, pg_size_pretty(pg_total_relation_size('encounters')) AS table_and_indexes,
       pg_size_pretty(pg_relation_size('enc_doc_gin')) AS gin_index
UNION ALL
SELECT 'patients', pg_size_pretty(pg_total_relation_size('patients')), NULL;
