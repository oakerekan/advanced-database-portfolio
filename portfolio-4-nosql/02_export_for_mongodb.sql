-- =====================================================================
-- MIT 8103 - Portfolio 4: export the documents as JSON Lines for mongoimport
-- Run from the portfolio-4-nosql folder (after 01_build_documents.sql):
--   mkdir -p data
--   psql -d laguna_care -f 02_export_for_mongodb.sql
-- Produces data/patients.json and data/encounters.json (one document per line)
-- =====================================================================
\pset tuples_only on
\pset format unaligned
\pset footer off

\o data/patients.json
SELECT doc::text FROM docstore.patients ORDER BY id;
\o data/encounters.json
SELECT doc::text FROM docstore.encounters ORDER BY id;
\o

-- small, readable samples kept in the repository
\o sample_documents/patient_LCH-0000010.json
SELECT jsonb_pretty(doc) FROM docstore.patients WHERE id = 'LCH-0000010';
\o sample_documents/encounter_emergency_example.json
SELECT jsonb_pretty(doc) FROM docstore.encounters
WHERE doc->>'type' = 'emergency' AND doc ? 'labResults' ORDER BY id LIMIT 1;
\o sample_documents/encounter_with_fbc_example.json
SELECT jsonb_pretty(doc) FROM docstore.encounters
WHERE doc @> '{"labResults":[{"test":"FBC"}]}' AND doc ? 'prescriptions' ORDER BY id LIMIT 1;
\o
