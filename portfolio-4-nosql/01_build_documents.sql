-- =====================================================================
-- MIT 8103 - Portfolio 4: build the document model from the relational data
-- Laguna Care Specialist Hospital
--
-- Turns the Portfolio 2 relational data (database laguna_care) into two
-- document collections, stored as JSONB in schema "docstore":
--   docstore.patients    one document per patient
--   docstore.encounters  one document per visit, with diagnoses,
--                        prescriptions, vital signs and lab results EMBEDDED
-- The same documents are exported to MongoDB (02_export_for_mongodb.sql)
-- and queried as JSONB in PostgreSQL (03_jsonb_document_store.sql).
--
-- Scope: the first 5,000 patients and all of their encounters.
-- Lab values are synthetic and derived deterministically from request_id.
-- Run: psql -d laguna_care -f 01_build_documents.sql
-- =====================================================================
SET search_path TO hospital;
DROP SCHEMA IF EXISTS docstore CASCADE;
CREATE SCHEMA docstore;

-- deterministic pseudo-random number in [0,1) from an id and a salt
CREATE FUNCTION docstore.h(id bigint, salt int) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$ SELECT ((id * 2654435761 + salt * 40503) % 100000) / 100000.0 $$;

-- ---------------------------------------------------------------------
-- Patients
-- ---------------------------------------------------------------------
CREATE TABLE docstore.patients AS
SELECT p.hospital_no AS id,
       jsonb_strip_nulls(jsonb_build_object(
         '_id',          p.hospital_no,
         'name',         jsonb_build_object('first', p.first_name, 'last', p.last_name),
         'dateOfBirth',  to_char(p.date_of_birth, 'YYYY-MM-DD'),
         'sex',          p.sex,
         'bloodGroup',   p.blood_group,
         'contact',      jsonb_build_object('phone', p.phone, 'address', p.address),
         'homeBranch',   b.branch_code,
         'insurance',    CASE WHEN p.provider_id IS NOT NULL THEN
                           jsonb_build_object('provider', ip.name, 'type', ip.provider_type, 'policyNo', p.policy_no) END,
         -- optional, variable-length fields: present only for some patients
         'allergies',    CASE WHEN p.patient_id % 10 = 0 THEN '["Penicillin"]'::jsonb
                              WHEN p.patient_id % 17 = 0 THEN '["Sulfonamides", "Peanuts"]'::jsonb END,
         'chronicConditions', CASE WHEN p.patient_id % 7 = 0 THEN '["Hypertension"]'::jsonb
                                   WHEN p.patient_id % 11 = 0 THEN '["Type 2 diabetes", "Hypertension"]'::jsonb END,
         'registeredAt', to_char(p.registered_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
       )) AS doc
FROM patient p
JOIN branch b ON b.branch_id = p.home_branch_id
LEFT JOIN insurance_provider ip ON ip.provider_id = p.provider_id
WHERE p.patient_id <= 5000;

ALTER TABLE docstore.patients ADD PRIMARY KEY (id);

-- ---------------------------------------------------------------------
-- Lab results with test-specific values (a different shape for each test)
-- ---------------------------------------------------------------------
CREATE TEMP TABLE lab_docs AS
SELECT lr.encounter_id,
       jsonb_strip_nulls(jsonb_build_object(
         'test',      t.test_code,
         'name',      t.name,
         'priority',  lr.priority,
         'status',    lr.status,
         'resultAt',  to_char(res.recorded_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
         'abnormal',  res.is_abnormal,
         'values',    CASE WHEN res.request_id IS NULL THEN NULL ELSE
           CASE t.test_code
             WHEN 'MP'    THEN jsonb_build_object(
                                 'result',  CASE WHEN res.is_abnormal THEN 'positive' ELSE 'negative' END,
                                 'species', CASE WHEN res.is_abnormal THEN 'P. falciparum' END,
                                 'parasitesPerUL', CASE WHEN res.is_abnormal THEN round(500 + docstore.h(lr.request_id,1) * 49500) END)
             WHEN 'FBC'   THEN jsonb_build_object(
                                 'hb_g_dL',          round(CASE WHEN res.is_abnormal THEN 6.5 + docstore.h(lr.request_id,1) * 4 ELSE 11.5 + docstore.h(lr.request_id,1) * 5 END, 1),
                                 'wbc_10e9_L',       round(4 + docstore.h(lr.request_id,2) * 7, 1),
                                 'platelets_10e9_L', round(150 + docstore.h(lr.request_id,3) * 250),
                                 'pcv_pct',          round(30 + docstore.h(lr.request_id,4) * 18))
             WHEN 'FBS'   THEN jsonb_build_object(
                                 'glucose_mmol_L',   round(CASE WHEN res.is_abnormal THEN 7.1 + docstore.h(lr.request_id,1) * 8 ELSE 3.9 + docstore.h(lr.request_id,1) * 1.6 END, 1))
             WHEN 'WIDAL' THEN jsonb_build_object(
                                 'O_titre', CASE WHEN res.is_abnormal THEN '1:320' ELSE '1:40' END,
                                 'H_titre', CASE WHEN res.is_abnormal THEN '1:160' ELSE '1:40' END)
             WHEN 'LIPID' THEN jsonb_build_object(
                                 'totalCholesterol_mmol_L', round(3.5 + docstore.h(lr.request_id,1) * 4, 1),
                                 'hdl_mmol_L',              round(0.8 + docstore.h(lr.request_id,2) * 1.2, 1),
                                 'ldl_mmol_L',              round(1.8 + docstore.h(lr.request_id,3) * 3, 1),
                                 'triglycerides_mmol_L',    round(0.6 + docstore.h(lr.request_id,4) * 2.4, 1))
             WHEN 'HIV'   THEN jsonb_build_object('result', CASE WHEN res.is_abnormal THEN 'reactive' ELSE 'non-reactive' END)
             WHEN 'GXM'   THEN jsonb_build_object('genotype', (ARRAY['AA','AA','AA','AS','AS','SS','AC'])[1 + floor(docstore.h(lr.request_id,1) * 7)::int])
             ELSE              jsonb_build_object('summary', res.summary)
           END END
       )) AS lab
FROM lab_request lr
JOIN lab_test t USING (test_id)
LEFT JOIN lab_result res USING (request_id)
JOIN encounter e USING (encounter_id)
WHERE e.patient_id <= 5000;

CREATE INDEX ON lab_docs (encounter_id);

-- ---------------------------------------------------------------------
-- Encounters: one self-contained document per visit
-- ---------------------------------------------------------------------
CREATE TABLE docstore.encounters AS
SELECT 'ENC-' || e.encounter_id AS id,
       jsonb_strip_nulls(jsonb_build_object(
         '_id',        'ENC-' || e.encounter_id,
         'patientId',  pt.hospital_no,
         'branch',     b.branch_code,
         'type',       e.encounter_type,
         'startedAt',  to_char(e.started_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
         'complaint',  e.chief_complaint,
         -- denormalised snapshot of the doctor AT THE TIME of the visit
         'doctor',     jsonb_build_object('staffId', s.staff_id, 'name', 'Dr ' || s.first_name || ' ' || s.last_name,
                                          'specialty', d.specialty),
         -- vital signs: emergency visits record extra fields
         'vitals',     jsonb_build_object(
                         'bp',     jsonb_build_object('systolic',  100 + round(docstore.h(e.encounter_id,1) * 70),
                                                      'diastolic', 60  + round(docstore.h(e.encounter_id,2) * 35)),
                         'tempC',  round(36.2 + docstore.h(e.encounter_id,3) * 3.3, 1),
                         'pulse',  60 + round(docstore.h(e.encounter_id,4) * 60))
                       || CASE WHEN e.encounter_type = 'emergency' THEN
                            jsonb_build_object('spo2_pct', 85 + round(docstore.h(e.encounter_id,5) * 14),
                                               'gcs',      9 + round(docstore.h(e.encounter_id,6) * 6))
                          ELSE '{}'::jsonb END,
         'diagnoses',     (SELECT jsonb_agg(jsonb_build_object('code', dg.icd10_code, 'description', dg.description,
                                                               'primary', dg.is_primary) ORDER BY NOT dg.is_primary)
                           FROM diagnosis dg WHERE dg.encounter_id = e.encounter_id),
         'prescriptions', (SELECT jsonb_agg(jsonb_build_object('drug', dr.generic_name, 'strength', dr.strength,
                                                               'form', dr.dosage_form, 'dose', pi.dose,
                                                               'frequency', pi.frequency, 'days', pi.duration_days,
                                                               'quantity', pi.quantity) ORDER BY dr.generic_name)
                           FROM prescription pr JOIN prescription_item pi USING (prescription_id) JOIN drug dr USING (drug_id)
                           WHERE pr.encounter_id = e.encounter_id),
         'labResults',    (SELECT jsonb_agg(l.lab ORDER BY l.lab->>'test') FROM lab_docs l WHERE l.encounter_id = e.encounter_id)
       )) AS doc
FROM encounter e
JOIN patient pt ON pt.patient_id = e.patient_id
JOIN branch b   ON b.branch_id = e.branch_id
JOIN staff s    ON s.staff_id = e.doctor_id
JOIN doctor d   ON d.staff_id = e.doctor_id
WHERE e.patient_id <= 5000;

ALTER TABLE docstore.encounters ADD PRIMARY KEY (id);
ANALYZE docstore.patients;
ANALYZE docstore.encounters;

SELECT 'patients' AS collection, count(*) AS documents, pg_size_pretty(sum(pg_column_size(doc))) AS data_size FROM docstore.patients
UNION ALL
SELECT 'encounters', count(*), pg_size_pretty(sum(pg_column_size(doc))) FROM docstore.encounters;
