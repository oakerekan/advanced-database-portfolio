-- =====================================================================
-- MIT 8103 - Portfolio 2: synthetic data generator
-- Lagoon Care Specialist Hospital
--
-- Loads realistic volumes of FAKE data so that query plans and indexes
-- behave as they would in a real hospital (small tables are always
-- scanned sequentially, so tiny demo data cannot show optimisation).
--
-- Run on an EMPTY schema:
--   psql -d lagoon_care -f ../portfolio-1-database-design/schema.sql
--   psql -d lagoon_care -f generate_data.sql
-- Takes about 1 minute. All names, numbers and records are fictitious.
-- =====================================================================
SET search_path TO hospital;
SELECT setseed(0.8103);                    -- repeatable "random" data
\timing on

-- ---------- Branches, departments ----------
INSERT INTO branch (branch_code, name, address, phone, opened_on) VALUES
 ('IKJ','Lagoon Care Ikeja','12 Allen Avenue, Ikeja','01-2000001','2015-03-01'),
 ('LKI','Lagoon Care Lekki','5 Admiralty Way, Lekki Phase 1','01-2000002','2019-07-15'),
 ('YAB','Lagoon Care Yaba','33 Herbert Macaulay Way, Yaba','01-2000003','2022-01-10');

-- 8 departments per branch -> department_id = (branch-1)*8 + k
INSERT INTO department (branch_id, name)
SELECT b, d FROM generate_series(1,3) b,
  unnest(ARRAY['General Medicine','Paediatrics','Obstetrics & Gynaecology','Surgery',
               'Cardiology','Orthopaedics','Emergency','ENT']) d;

-- ---------- Staff: ids 1-150 doctors, 151-450 other roles ----------
INSERT INTO staff (staff_no, home_branch_id, department_id, first_name, last_name, role, email, hire_date)
SELECT 'LC-S-' || lpad(i::text,5,'0'),
       (i-1) % 3 + 1,
       CASE WHEN i <= 150 THEN ((i-1)%3)*8 + ((i-1)/3)%8 + 1
            WHEN (i-151)%6 = 0 THEN ((i-1)%3)*8 + (i%8) + 1      -- nurses get a department
            ELSE NULL END,
       (ARRAY['Adaeze','Tunde','Halima','Chukwuemeka','Folake','Ibrahim','Ngozi','Olumide','Aisha','Emeka',
              'Funmilayo','Yusuf','Chiamaka','Babajide','Zainab','Obinna','Temitope','Musa','Ifeoma','Segun'])[1 + i % 20],
       (ARRAY['Okafor','Bakare','Musa','Adeyemi','Eze','Bello','Okonkwo','Adebayo','Abubakar','Nwosu',
              'Ogunleye','Danjuma','Obi','Afolabi','Lawal','Uche','Oyelaran','Ibekwe','Sani','Akinola'])[1 + (i*7) % 20],
       CASE WHEN i <= 150 THEN 'doctor'
            ELSE (ARRAY['nurse','lab_scientist','pharmacist','receptionist','billing_officer','admin'])[(i-151)%6 + 1] END,
       'staff' || i || '@lagooncare.ng',
       DATE '2015-03-01' + (random()*3500)::int
FROM generate_series(1,450) i;

INSERT INTO doctor (staff_id, specialty, mdcn_licence_no)
SELECT s.staff_id,
       CASE d.name WHEN 'General Medicine' THEN 'Internal Medicine' WHEN 'Obstetrics & Gynaecology' THEN 'Obstetrics'
                   WHEN 'Emergency' THEN 'Emergency Medicine' ELSE d.name END,
       'MDCN/R/' || (40000 + s.staff_id)
FROM staff s JOIN department d ON d.department_id = s.department_id
WHERE s.role = 'doctor';

-- ---------- Insurance ----------
INSERT INTO insurance_provider (name, provider_type, phone) VALUES
 ('Hygeia HMO','HMO','0700-HYGEIA'), ('AXA Mansard Health','HMO','0700-AXAMAN'),
 ('Reliance HMO','HMO','0700-RELIAN'), ('Avon HMO','HMO','0700-AVONHM'),
 ('NHIA (Formal Sector)','NHIA','0800-NHIA00'), ('Leadway Health','HMO','0700-LEADWY');

-- ---------- Patients (60,000) ----------
INSERT INTO patient (hospital_no, home_branch_id, first_name, last_name, date_of_birth, sex, blood_group,
                     phone, address, provider_id, policy_no, registered_at)
SELECT 'LCH-' || lpad(i::text,7,'0'),
       CASE WHEN r1 < 0.5 THEN 1 WHEN r1 < 0.8 THEN 2 ELSE 3 END,
       (ARRAY['Chinedu','Ngozi','Oluwaseun','Amina','Emeka','Blessing','Ibrahim','Funke','Uchenna','Fatima',
              'Tolulope','Kelechi','Hauwa','Babatunde','Chioma','Abdullahi','Yetunde','Ikenna','Bukola','Sadiq',
              'Nkechi','Damilola','Usman','Adaobi','Femi','Maryam','Chidi','Kemi','Aliyu','Ebere'])[1 + floor(random()*30)::int],
       (ARRAY['Okafor','Adeyemi','Eze','Bello','Okonkwo','Adebayo','Abubakar','Nwosu','Ogunleye','Danjuma',
              'Obi','Afolabi','Lawal','Uche','Oyelaran','Ibekwe','Sani','Akinola','Chukwu','Balogun',
              'Mohammed','Olawale','Nnamdi','Ojo','Garba','Onyeka','Fashola','Yakubu','Odili','Salami',
              'Anyanwu','Adeleke','Umar','Ezeh','Oladipo','Ahmed','Ugwu','Bankole','Idris','Okeke'])[1 + floor(random()*40)::int],
       DATE '1940-01-01' + (random()*30000)::int,
       CASE WHEN random() < 0.52 THEN 'F' ELSE 'M' END,
       (ARRAY['O+','O+','O+','A+','A+','B+','B+','AB+','O-','A-','B-','AB-'])[1 + floor(random()*12)::int],
       '080' || lpad((10000000 + i)::text, 8, '0'),
       (1 + floor(random()*200))::int || ' ' ||
       (ARRAY['Allen Avenue','Admiralty Way','Herbert Macaulay Way','Awolowo Road','Ikorodu Road','Adeola Odeku Street',
              'Bode Thomas Street','Opebi Road','Lekki-Epe Expressway','Agege Motor Road'])[1 + floor(random()*10)::int] || ', Lagos',
       CASE WHEN r2 < 0.45 THEN 1 + (i % 6) END,
       CASE WHEN r2 < 0.45 THEN 'POL-' || lpad(i::text,8,'0') END,
       TIMESTAMPTZ '2015-03-01' + random() * INTERVAL '4000 days'
FROM (SELECT i, random() r1, random() r2 FROM generate_series(1,60000) i) g;

-- ---------- Appointments (300,000) ----------
-- 2,000 per doctor over ~680 days, at most 3 per doctor per day in
-- 09:00 / 11:00 / 13:00 / 15:00 slots, so the no-double-booking
-- exclusion constraint is always satisfied.
INSERT INTO appointment (patient_id, doctor_id, branch_id, slot, status, reason, booked_by, created_at)
SELECT 1 + floor(random()*60000)::bigint,
       d,
       CASE WHEN random() < 0.85 THEN (d-1)%3 + 1 ELSE 1 + floor(random()*3)::int END,  -- 15% at another branch
       tstzrange(st, st + INTERVAL '30 minutes'),
       CASE WHEN st > TIMESTAMPTZ '2026-11-14' THEN 'booked'
            WHEN rs < 0.85 THEN 'completed' WHEN rs < 0.93 THEN 'cancelled' ELSE 'no_show' END,
       (ARRAY['Routine check-up','Follow-up visit','Fever','Antenatal visit','Blood pressure review',
              'Chest pain','Child immunisation','Back pain','Diabetes review','Skin rash'])[1 + floor(random()*10)::int],
       154 + 6*floor(random()*50)::int,                                                 -- a receptionist
       st - random() * INTERVAL '14 days'
FROM (SELECT d, k, random() rs,
             TIMESTAMPTZ '2025-01-01 09:00+01' + floor(k*0.34) * INTERVAL '1 day' + (k%4) * INTERVAL '2 hours' AS st
      FROM generate_series(1,150) d, generate_series(0,1999) k) a;

-- ---------- Encounters: one per completed appointment + 20,000 walk-ins ----------
INSERT INTO encounter (patient_id, doctor_id, branch_id, appointment_id, encounter_type, started_at, chief_complaint)
SELECT patient_id, doctor_id, branch_id, appointment_id,
       CASE WHEN random() < 0.25 THEN 'follow_up' ELSE 'outpatient' END,
       lower(slot) + INTERVAL '5 minutes', reason
FROM appointment WHERE status = 'completed';

INSERT INTO encounter (patient_id, doctor_id, branch_id, encounter_type, started_at, chief_complaint)
SELECT 1 + floor(random()*60000)::bigint, 1 + floor(random()*150)::int, 1 + floor(random()*3)::int,
       'emergency', TIMESTAMPTZ '2025-01-01' + random() * INTERVAL '680 days',
       (ARRAY['Road traffic accident','High fever','Severe abdominal pain','Difficulty breathing',
              'Convulsions','Bleeding','Burns','Chest pain'])[1 + floor(random()*8)::int]
FROM generate_series(1,20000);

-- ---------- Diagnoses (skewed: malaria and hypertension are most common) ----------
WITH codes(idx, code, descr) AS (
  SELECT * FROM unnest(
    ARRAY[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20],
    ARRAY['B54','I10','A01.0','E11.9','J06.9','N39.0','K29.7','J18.9','O80','M54.5',
          'A09','L30.9','D50.9','R51','H66.9','J45.9','K35.8','S06.0','B20','Z00.0'],
    ARRAY['Malaria, unspecified','Essential hypertension','Typhoid fever','Type 2 diabetes mellitus',
          'Acute upper respiratory infection','Urinary tract infection','Gastritis','Pneumonia',
          'Normal delivery','Low back pain','Gastroenteritis','Dermatitis','Iron deficiency anaemia',
          'Headache','Otitis media','Asthma','Appendicitis','Concussion','HIV disease','General examination'])
),
e AS (
  SELECT encounter_id,
         1 + floor(20 * power(random(), 2))::int AS p,           -- skew towards low index
         1 + floor(random()*19)::int            AS shift,
         random() AS r
  FROM encounter
)
INSERT INTO diagnosis (encounter_id, icd10_code, description, is_primary)
SELECT e.encounter_id, c.code, c.descr, TRUE FROM e JOIN codes c ON c.idx = e.p
UNION ALL
SELECT e.encounter_id, c.code, c.descr, FALSE FROM e JOIN codes c ON c.idx = ((e.p - 1 + e.shift) % 20) + 1
WHERE e.r < 0.30;

-- ---------- Drugs (120) and branch stock ----------
INSERT INTO drug (nafdac_no, generic_name, brand_name, dosage_form, strength, unit_price)
SELECT 'A4-' || lpad(i::text,4,'0') || 'L',
       g.name, g.name || ' ' || (ARRAY['Emzor','Fidson','May & Baker','GSK'])[1 + (i-1)/30],
       g.form, (ARRAY['100','250','500','1000'])[1 + (i-1)/30] || ' mg',
       round((50 + random()*4950)::numeric, 2)
FROM generate_series(1,120) i
JOIN (SELECT row_number() OVER () AS n, name, form FROM unnest(
        ARRAY['Artemether/Lumefantrine','Paracetamol','Amoxicillin','Metformin','Amlodipine','Ciprofloxacin',
              'Ibuprofen','Omeprazole','Lisinopril','Metronidazole','Ceftriaxone','Diclofenac','Folic Acid',
              'Ferrous Sulphate','Salbutamol','Prednisolone','Losartan','Azithromycin','Vitamin C','Chloroquine',
              'Hydrochlorothiazide','Glibenclamide','Cetirizine','Loratadine','Tramadol','Insulin','Oxytocin',
              'Zinc Sulphate','ORS','Albendazole'],
        ARRAY['tablet','tablet','capsule','tablet','tablet','tablet','tablet','capsule','tablet','tablet',
              'injection','tablet','tablet','tablet','inhaler','tablet','tablet','tablet','tablet','tablet',
              'tablet','tablet','tablet','tablet','capsule','injection','injection','tablet','syrup','tablet'])
      AS t(name, form)) g ON g.n = (i-1) % 30 + 1;

INSERT INTO branch_drug_stock (branch_id, drug_id, quantity, reorder_level)
SELECT b, d, floor(random()*600)::int, 50 FROM generate_series(1,3) b, generate_series(1,120) d;

-- ---------- Prescriptions (~60% of encounters) and items (1-3 drugs) ----------
INSERT INTO prescription (encounter_id, prescribed_at, status)
SELECT encounter_id, started_at + INTERVAL '20 minutes',
       CASE WHEN random() < 0.92 THEN 'dispensed' ELSE 'pending' END
FROM encounter WHERE random() < 0.60;

INSERT INTO prescription_item (prescription_id, drug_id, dose, frequency, duration_days, quantity, quantity_dispensed)
SELECT p.prescription_id,
       1 + ((p.base + k*37) % 120),                              -- 37*k mod 120 keeps the 1-3 drugs distinct
       (ARRAY['1 tablet','2 tablets','5 ml','10 ml','1 vial'])[1 + floor(random()*5)::int],
       (ARRAY['once daily','12-hourly','8-hourly','6-hourly'])[1 + floor(random()*4)::int],
       d.days, d.days * 2,
       CASE WHEN p.status = 'dispensed' THEN d.days * 2 ELSE 0 END
FROM (SELECT prescription_id, status, floor(120 * power(random(),3))::int AS base,
             1 + floor(random()*3)::int AS n
      FROM prescription) p
CROSS JOIN LATERAL generate_series(0, p.n - 1) k
CROSS JOIN LATERAL (SELECT (ARRAY[3,5,7,14,30])[1 + floor(random()*5)::int] AS days) d;

-- ---------- Lab tests (30), requests (~40% of encounters), results ----------
INSERT INTO lab_test (test_code, name, specimen_type, price)
SELECT * FROM unnest(
 ARRAY['MP','FBC','WIDAL','FBS','HBA1C','LFT','EUCR','LIPID','UA','UMCS','HIV','HBSAG','HCV','VDRL','PT',
       'PCV','ESR','GXM','BG','TFT','PSA','CRP','SMCS','STOOL','MANTOUX','CXR','ECG','USS','HVS','SCS'],
 ARRAY['Malaria Parasite','Full Blood Count','Widal Test','Fasting Blood Sugar','HbA1c','Liver Function Test',
       'Electrolytes, Urea & Creatinine','Lipid Profile','Urinalysis','Urine M/C/S','HIV Screening','Hepatitis B sAg',
       'Hepatitis C Antibody','VDRL','Pregnancy Test','Packed Cell Volume','ESR','Genotype','Blood Group',
       'Thyroid Function Test','PSA','C-Reactive Protein','Sputum M/C/S','Stool Microscopy','Mantoux Test',
       'Chest X-Ray','Electrocardiogram','Ultrasound Scan','High Vaginal Swab','Semen Analysis'],
 ARRAY['blood','blood','blood','blood','blood','blood','blood','blood','urine','urine','blood','blood','blood',
       'blood','urine','blood','blood','blood','blood','blood','blood','blood','sputum','stool','skin','imaging',
       'imaging','imaging','swab','semen'],
 ARRAY[2500,5000,3000,2000,8000,12000,15000,10000,2000,6000,3000,3500,5000,3000,1500,1500,2000,4000,1500,
       25000,18000,7000,6000,2500,3000,15000,10000,20000,5000,6000]::numeric[]);

INSERT INTO lab_request (encounter_id, test_id, requested_at, priority, status)
SELECT e.encounter_id,
       1 + ((e.base + k*7) % 30),
       e.started_at + INTERVAL '15 minutes',
       CASE WHEN e.encounter_type = 'emergency' THEN 'urgent' WHEN random() < 0.05 THEN 'stat' ELSE 'routine' END,
       CASE WHEN e.started_at > TIMESTAMPTZ '2026-11-01' AND random() < 0.5 THEN 'requested'
            WHEN random() < 0.02 THEN 'cancelled' ELSE 'completed' END
FROM (SELECT encounter_id, started_at, encounter_type,
             floor(30 * power(random(),2))::int AS base, 1 + floor(random()*2)::int AS n
      FROM encounter WHERE random() < 0.40) e
CROSS JOIN LATERAL generate_series(0, e.n - 1) k;

INSERT INTO lab_result (request_id, recorded_by, recorded_at, summary, is_abnormal)
SELECT request_id, 152 + 6*floor(random()*50)::int,
       requested_at + (1 + random()*47) * INTERVAL '1 hour',
       CASE WHEN ab THEN 'Abnormal - see detailed report' ELSE 'Within normal limits' END, ab
FROM (SELECT request_id, requested_at, random() < 0.2 AS ab FROM lab_request WHERE status = 'completed') r;

-- ---------- Wards (30), beds (600), admissions (12,000) ----------
INSERT INTO ward (branch_id, name, ward_type, daily_rate)
SELECT b, 'Ward ' || chr(64 + w),
       (ARRAY['general','general','general','maternity','paediatric','icu','surgical','surgical','private','private'])[w],
       (ARRAY[15000,15000,15000,25000,20000,120000,30000,30000,60000,60000])[w]
FROM generate_series(1,3) b, generate_series(1,10) w;

INSERT INTO bed (ward_id, bed_label)
SELECT w, chr(64 + ((w-1)%10) + 1) || '-' || lpad(n::text,2,'0')
FROM generate_series(1,30) w, generate_series(1,20) n;

-- Each bed gets 20 stays, each inside its own 30-day window, so stays never overlap.
INSERT INTO admission (patient_id, bed_id, admitting_doctor_id, admitted_at, discharged_at, discharge_summary)
SELECT 1 + floor(random()*60000)::bigint, b, 1 + floor(random()*150)::int,
       a, a + (1 + floor(random()*10)) * INTERVAL '1 day' + random() * INTERVAL '8 hours',
       'Discharged in stable condition'
FROM (SELECT b, j, TIMESTAMPTZ '2025-01-01 10:00+01' + j * INTERVAL '30 days' + random() * INTERVAL '5 days' AS a
      FROM generate_series(1,600) b, generate_series(0,19) j) s;

-- ---------- Invoices: one per encounter + one per admission ----------
INSERT INTO invoice (invoice_no, patient_id, branch_id, encounter_id, issued_at)
SELECT 'INV-' || lpad(encounter_id::text, 8, '0'), patient_id, branch_id, encounter_id,
       started_at + INTERVAL '1 hour'
FROM encounter;

INSERT INTO invoice (invoice_no, patient_id, branch_id, admission_id, issued_at)
SELECT 'ADM-' || lpad(a.admission_id::text, 8, '0'), a.patient_id, w.branch_id, a.admission_id, a.discharged_at
FROM admission a JOIN bed b USING (bed_id) JOIN ward w USING (ward_id);

-- Line 1: consultation fee
INSERT INTO invoice_item (invoice_id, line_no, item_type, description, quantity, unit_price)
SELECT i.invoice_id, 1, 'consultation',
       CASE WHEN e.encounter_type = 'emergency' THEN 'Emergency consultation' ELSE 'Doctor consultation' END,
       1, CASE WHEN e.encounter_type = 'emergency' THEN 20000 ELSE 10000 END
FROM invoice i JOIN encounter e USING (encounter_id);

-- Lines 2+: drugs (price at time of billing)
INSERT INTO invoice_item (invoice_id, line_no, item_type, description, quantity, unit_price)
SELECT i.invoice_id,
       1 + row_number() OVER (PARTITION BY i.invoice_id ORDER BY pi.drug_id),
       'drug', d.generic_name || ' ' || d.strength, pi.quantity, d.unit_price
FROM invoice i
JOIN prescription p ON p.encounter_id = i.encounter_id
JOIN prescription_item pi USING (prescription_id)
JOIN drug d USING (drug_id);

-- Lines 50+: lab tests
INSERT INTO invoice_item (invoice_id, line_no, item_type, description, quantity, unit_price)
SELECT i.invoice_id, 49 + row_number() OVER (PARTITION BY i.invoice_id ORDER BY lr.test_id),
       'lab', t.name, 1, t.price
FROM invoice i
JOIN lab_request lr ON lr.encounter_id = i.encounter_id AND lr.status <> 'cancelled'
JOIN lab_test t USING (test_id);

-- Admission invoices: bed days
INSERT INTO invoice_item (invoice_id, line_no, item_type, description, quantity, unit_price)
SELECT i.invoice_id, 1, 'bed', 'Bed charge - ' || w.name,
       ceil(extract(epoch FROM a.discharged_at - a.admitted_at) / 86400), w.daily_rate
FROM invoice i JOIN admission a USING (admission_id) JOIN bed b USING (bed_id) JOIN ward w USING (ward_id);

-- ---------- Payments: 80% paid in full, 10% part-paid, 10% unpaid ----------
INSERT INTO payment (invoice_id, amount, method, provider_id, reference, received_by, paid_at)
SELECT t.invoice_id,
       CASE WHEN t.r < 0.80 THEN t.total ELSE round(t.total * 0.5, 2) END,
       CASE WHEN p.provider_id IS NOT NULL AND t.m < 0.6 THEN 'insurance'
            ELSE (ARRAY['cash','card','transfer','pos'])[1 + floor(t.m2*4)::int] END,
       CASE WHEN p.provider_id IS NOT NULL AND t.m < 0.6 THEN p.provider_id END,
       'REF-' || lpad(t.invoice_id::text, 9, '0'),
       155 + 6*floor(random()*50)::int,                                    -- a billing officer
       t.issued_at + random() * INTERVAL '3 days'
FROM (SELECT i.invoice_id, i.patient_id, i.issued_at, b.total_amount AS total,
             random() r, random() m, random() m2
      FROM invoice i JOIN invoice_balance b USING (invoice_id)) t
JOIN patient p USING (patient_id)
WHERE t.r < 0.90 AND t.total > 0;

UPDATE invoice i SET status = CASE WHEN b.amount_paid = 0 THEN 'unpaid'
                                   WHEN b.balance_due > 0 THEN 'part_paid' ELSE 'paid' END
FROM invoice_balance b WHERE b.invoice_id = i.invoice_id;

\timing off
VACUUM ANALYZE;

-- ---------- Row counts ----------
SELECT relname AS table_name, n_live_tup AS rows
FROM pg_stat_user_tables WHERE schemaname = 'hospital' ORDER BY n_live_tup DESC;
