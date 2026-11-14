-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 1
-- Case study : Lagoon Care Specialist Hospital (multi-branch, Lagos)
-- DBMS       : PostgreSQL 16
-- File       : schema.sql  - full relational schema with keys & constraints
-- Run        : psql -d lagoon_care -f schema.sql
-- =====================================================================

DROP SCHEMA IF EXISTS hospital CASCADE;
CREATE SCHEMA hospital;
SET search_path TO hospital;

-- Needed for EXCLUDE constraints that mix "=" on integers with "&&" on ranges
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ---------------------------------------------------------------------
-- 1. ORGANISATION
-- ---------------------------------------------------------------------
CREATE TABLE branch (
    branch_id     SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    branch_code   CHAR(3)      NOT NULL UNIQUE,          -- e.g. IKJ, LKI, YAB
    name          VARCHAR(100) NOT NULL UNIQUE,
    address       VARCHAR(200) NOT NULL,
    city          VARCHAR(60)  NOT NULL DEFAULT 'Lagos',
    phone         VARCHAR(20)  NOT NULL,
    opened_on     DATE         NOT NULL
);

CREATE TABLE department (
    department_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    branch_id     SMALLINT     NOT NULL REFERENCES branch(branch_id),
    name          VARCHAR(80)  NOT NULL,                 -- e.g. Cardiology
    CONSTRAINT uq_department_per_branch UNIQUE (branch_id, name)
);

CREATE TABLE staff (
    staff_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    staff_no      VARCHAR(12)  NOT NULL UNIQUE,          -- e.g. LC-S-00042
    branch_id     SMALLINT     NOT NULL REFERENCES branch(branch_id),
    department_id INT          REFERENCES department(department_id),
    first_name    VARCHAR(50)  NOT NULL,
    last_name     VARCHAR(50)  NOT NULL,
    role          VARCHAR(20)  NOT NULL
        CHECK (role IN ('doctor','nurse','lab_scientist','pharmacist',
                        'receptionist','billing_officer','admin')),
    email         VARCHAR(120) NOT NULL UNIQUE,
    phone         VARCHAR(20),
    hire_date     DATE         NOT NULL,
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE
);

-- Specialisation (IS-A): every doctor is a staff member with extra attributes.
CREATE TABLE doctor (
    staff_id       INT PRIMARY KEY REFERENCES staff(staff_id) ON DELETE CASCADE,
    specialty      VARCHAR(60) NOT NULL,
    mdcn_licence_no VARCHAR(20) NOT NULL UNIQUE           -- Medical & Dental Council of Nigeria
);

-- ---------------------------------------------------------------------
-- 2. PATIENTS & INSURANCE
-- ---------------------------------------------------------------------
CREATE TABLE insurance_provider (
    provider_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          VARCHAR(100) NOT NULL UNIQUE,
    provider_type VARCHAR(10)  NOT NULL CHECK (provider_type IN ('HMO','NHIA','PRIVATE')),
    phone         VARCHAR(20)
);

CREATE TABLE patient (
    patient_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    hospital_no     VARCHAR(15)  NOT NULL UNIQUE,        -- shared across all branches
    home_branch_id  SMALLINT     NOT NULL REFERENCES branch(branch_id),
    first_name      VARCHAR(50)  NOT NULL,
    last_name       VARCHAR(50)  NOT NULL,
    date_of_birth   DATE         NOT NULL CHECK (date_of_birth <= CURRENT_DATE),
    sex             CHAR(1)      NOT NULL CHECK (sex IN ('M','F')),
    blood_group     VARCHAR(3)   CHECK (blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    phone           VARCHAR(20)  NOT NULL,
    email           VARCHAR(120),
    address         VARCHAR(200),
    next_of_kin_name  VARCHAR(100),
    next_of_kin_phone VARCHAR(20),
    provider_id     INT          REFERENCES insurance_provider(provider_id),
    policy_no       VARCHAR(30),
    registered_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    -- a policy number only makes sense together with a provider
    CONSTRAINT chk_policy_needs_provider CHECK (policy_no IS NULL OR provider_id IS NOT NULL),
    CONSTRAINT uq_policy UNIQUE (provider_id, policy_no)
);

-- ---------------------------------------------------------------------
-- 3. APPOINTMENTS & CLINICAL ENCOUNTERS
-- ---------------------------------------------------------------------
CREATE TABLE appointment (
    appointment_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id      BIGINT      NOT NULL REFERENCES patient(patient_id),
    doctor_id       INT         NOT NULL REFERENCES doctor(staff_id),
    branch_id       SMALLINT    NOT NULL REFERENCES branch(branch_id),
    slot            TSTZRANGE   NOT NULL,                -- [start, end)
    status          VARCHAR(12) NOT NULL DEFAULT 'booked'
        CHECK (status IN ('booked','checked_in','completed','cancelled','no_show')),
    reason          VARCHAR(200),
    booked_by       INT         REFERENCES staff(staff_id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_slot_valid CHECK (NOT isempty(slot) AND lower(slot) IS NOT NULL AND upper(slot) IS NOT NULL),
    -- Business rule: a doctor can never have two overlapping active appointments.
    CONSTRAINT no_doctor_double_booking EXCLUDE USING gist (
        doctor_id WITH =, slot WITH &&
    ) WHERE (status <> 'cancelled')
);

CREATE TABLE encounter (                                  -- a consultation / visit
    encounter_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id      BIGINT      NOT NULL REFERENCES patient(patient_id),
    doctor_id       INT         NOT NULL REFERENCES doctor(staff_id),
    branch_id       SMALLINT    NOT NULL REFERENCES branch(branch_id),
    appointment_id  BIGINT      UNIQUE REFERENCES appointment(appointment_id), -- NULL = walk-in/emergency
    encounter_type  VARCHAR(12) NOT NULL DEFAULT 'outpatient'
        CHECK (encounter_type IN ('outpatient','emergency','inpatient','follow_up')),
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    chief_complaint VARCHAR(300) NOT NULL,
    clinical_notes  TEXT
);

CREATE TABLE diagnosis (
    diagnosis_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    encounter_id    BIGINT      NOT NULL REFERENCES encounter(encounter_id) ON DELETE CASCADE,
    icd10_code      VARCHAR(8)  NOT NULL,                -- e.g. B54 (malaria), I10 (hypertension)
    description     VARCHAR(200) NOT NULL,
    is_primary      BOOLEAN     NOT NULL DEFAULT FALSE,
    CONSTRAINT uq_diagnosis_per_encounter UNIQUE (encounter_id, icd10_code)
);
-- At most ONE primary diagnosis per encounter (partial unique index)
CREATE UNIQUE INDEX uq_one_primary_diagnosis ON diagnosis(encounter_id) WHERE is_primary;

-- ---------------------------------------------------------------------
-- 4. PHARMACY
-- ---------------------------------------------------------------------
CREATE TABLE drug (
    drug_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nafdac_no     VARCHAR(20)  UNIQUE,                   -- NAFDAC registration number
    generic_name  VARCHAR(100) NOT NULL,
    brand_name    VARCHAR(100),
    dosage_form   VARCHAR(20)  NOT NULL CHECK (dosage_form IN
                    ('tablet','capsule','syrup','injection','cream','drops','inhaler')),
    strength      VARCHAR(30)  NOT NULL,                 -- e.g. 500 mg
    unit_price    NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    CONSTRAINT uq_drug UNIQUE (generic_name, dosage_form, strength, brand_name)
);

-- Each branch keeps its own stock: M:N between branch and drug.
CREATE TABLE branch_drug_stock (
    branch_id     SMALLINT NOT NULL REFERENCES branch(branch_id),
    drug_id       INT      NOT NULL REFERENCES drug(drug_id),
    quantity      INT      NOT NULL DEFAULT 0 CHECK (quantity >= 0),   -- stock can never go negative
    reorder_level INT      NOT NULL DEFAULT 20 CHECK (reorder_level >= 0),
    PRIMARY KEY (branch_id, drug_id)
);

CREATE TABLE prescription (
    prescription_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    encounter_id    BIGINT      NOT NULL REFERENCES encounter(encounter_id),
    prescribed_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    status          VARCHAR(12) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','partially_dispensed','dispensed','cancelled'))
);

CREATE TABLE prescription_item (
    prescription_id BIGINT      NOT NULL REFERENCES prescription(prescription_id) ON DELETE CASCADE,
    drug_id         INT         NOT NULL REFERENCES drug(drug_id),
    dose            VARCHAR(30) NOT NULL,                -- e.g. 1 tablet
    frequency       VARCHAR(30) NOT NULL,                -- e.g. 8-hourly
    duration_days   SMALLINT    NOT NULL CHECK (duration_days > 0),
    quantity        INT         NOT NULL CHECK (quantity > 0),
    quantity_dispensed INT      NOT NULL DEFAULT 0,
    PRIMARY KEY (prescription_id, drug_id),
    CONSTRAINT chk_not_over_dispensed CHECK (quantity_dispensed BETWEEN 0 AND quantity)
);

-- ---------------------------------------------------------------------
-- 5. LABORATORY
-- ---------------------------------------------------------------------
CREATE TABLE lab_test (                                   -- catalogue of available tests
    test_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    test_code     VARCHAR(12)  NOT NULL UNIQUE,          -- e.g. FBC, MP, LFT
    name          VARCHAR(100) NOT NULL,
    specimen_type VARCHAR(20)  NOT NULL,                 -- blood, urine, stool ...
    price         NUMERIC(10,2) NOT NULL CHECK (price >= 0)
);

CREATE TABLE lab_request (
    request_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    encounter_id  BIGINT      NOT NULL REFERENCES encounter(encounter_id),
    test_id       INT         NOT NULL REFERENCES lab_test(test_id),
    requested_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    priority      VARCHAR(8)  NOT NULL DEFAULT 'routine' CHECK (priority IN ('routine','urgent','stat')),
    status        VARCHAR(12) NOT NULL DEFAULT 'requested'
        CHECK (status IN ('requested','collected','completed','cancelled')),
    CONSTRAINT uq_test_per_encounter UNIQUE (encounter_id, test_id)
);

-- 1:1 with lab_request. Detailed, test-specific values (which differ for
-- every test) are deliberately kept for the NoSQL model in Portfolio 4.
CREATE TABLE lab_result (
    request_id    BIGINT PRIMARY KEY REFERENCES lab_request(request_id),
    recorded_by   INT         NOT NULL REFERENCES staff(staff_id),
    recorded_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    summary       VARCHAR(500) NOT NULL,
    is_abnormal   BOOLEAN     NOT NULL DEFAULT FALSE
);

-- ---------------------------------------------------------------------
-- 6. WARDS & ADMISSIONS
-- ---------------------------------------------------------------------
CREATE TABLE ward (
    ward_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    branch_id     SMALLINT    NOT NULL REFERENCES branch(branch_id),
    name          VARCHAR(60) NOT NULL,
    ward_type     VARCHAR(12) NOT NULL CHECK (ward_type IN
                    ('general','maternity','paediatric','icu','surgical','private')),
    daily_rate    NUMERIC(10,2) NOT NULL CHECK (daily_rate >= 0),
    CONSTRAINT uq_ward_per_branch UNIQUE (branch_id, name)
);

CREATE TABLE bed (
    bed_id        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ward_id       INT         NOT NULL REFERENCES ward(ward_id),
    bed_label     VARCHAR(10) NOT NULL,                  -- e.g. B-07
    is_in_service BOOLEAN     NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_bed_per_ward UNIQUE (ward_id, bed_label)
);

CREATE TABLE admission (
    admission_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id      BIGINT      NOT NULL REFERENCES patient(patient_id),
    bed_id          INT         NOT NULL REFERENCES bed(bed_id),
    admitting_doctor_id INT     NOT NULL REFERENCES doctor(staff_id),
    encounter_id    BIGINT      REFERENCES encounter(encounter_id),
    admitted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    discharged_at   TIMESTAMPTZ,
    discharge_summary TEXT,
    CONSTRAINT chk_discharge_after_admit CHECK (discharged_at IS NULL OR discharged_at > admitted_at),
    -- A bed cannot hold two patients over overlapping periods.
    CONSTRAINT no_bed_double_occupancy EXCLUDE USING gist (
        bed_id WITH =, tstzrange(admitted_at, discharged_at) WITH &&
    )
);
-- A patient can have at most one open (not yet discharged) admission.
CREATE UNIQUE INDEX uq_one_open_admission ON admission(patient_id) WHERE discharged_at IS NULL;

-- ---------------------------------------------------------------------
-- 7. BILLING
-- ---------------------------------------------------------------------
CREATE TABLE invoice (
    invoice_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_no    VARCHAR(20) NOT NULL UNIQUE,
    patient_id    BIGINT      NOT NULL REFERENCES patient(patient_id),
    branch_id     SMALLINT    NOT NULL REFERENCES branch(branch_id),
    encounter_id  BIGINT      REFERENCES encounter(encounter_id),
    admission_id  BIGINT      REFERENCES admission(admission_id),
    issued_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    status        VARCHAR(10) NOT NULL DEFAULT 'unpaid'
        CHECK (status IN ('unpaid','part_paid','paid','void')),
    -- every invoice must be for a visit or an admission (or both)
    CONSTRAINT chk_invoice_source CHECK (encounter_id IS NOT NULL OR admission_id IS NOT NULL)
);

CREATE TABLE invoice_item (
    invoice_id    BIGINT       NOT NULL REFERENCES invoice(invoice_id) ON DELETE CASCADE,
    line_no       SMALLINT     NOT NULL,
    item_type     VARCHAR(12)  NOT NULL CHECK (item_type IN
                    ('consultation','drug','lab','bed','procedure','other')),
    description   VARCHAR(200) NOT NULL,
    quantity      NUMERIC(8,2) NOT NULL CHECK (quantity > 0),
    unit_price    NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),  -- price at time of billing
    PRIMARY KEY (invoice_id, line_no)
);

CREATE TABLE payment (
    payment_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id    BIGINT       NOT NULL REFERENCES invoice(invoice_id),
    amount        NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    method        VARCHAR(10)  NOT NULL CHECK (method IN ('cash','card','transfer','pos','insurance')),
    provider_id   INT          REFERENCES insurance_provider(provider_id),
    reference     VARCHAR(50)  UNIQUE,                   -- bank/POS reference, prevents double posting
    received_by   INT          REFERENCES staff(staff_id),
    paid_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_insurance_payment CHECK (method <> 'insurance' OR provider_id IS NOT NULL)
);

-- ---------------------------------------------------------------------
-- 8. DERIVED DATA AS A VIEW (not stored -> avoids update anomalies)
-- ---------------------------------------------------------------------
CREATE VIEW invoice_balance AS
SELECT i.invoice_id,
       i.invoice_no,
       i.patient_id,
       COALESCE(t.total, 0)                         AS total_amount,
       COALESCE(p.paid, 0)                          AS amount_paid,
       COALESCE(t.total, 0) - COALESCE(p.paid, 0)   AS balance_due
FROM invoice i
LEFT JOIN (SELECT invoice_id, SUM(quantity * unit_price) AS total
           FROM invoice_item GROUP BY invoice_id) t USING (invoice_id)
LEFT JOIN (SELECT invoice_id, SUM(amount) AS paid
           FROM payment GROUP BY invoice_id) p USING (invoice_id);
