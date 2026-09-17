-- ============================================================================
-- healthcare-data-analytics : 03_star_schema.sql
--
-- Dimension and fact tables. This is the part of the project that deliberately
-- shows off Day 9-11 of the study plan: grain-first design, degenerate
-- dimensions, additive vs. semi-additive measures, and a Type 2 SCD on
-- dim_patient.
--
-- Grain declarations (write these down before touching a CREATE TABLE --
-- getting the grain wrong is the single biggest source of double-counted
-- or missing rows in a star schema):
--   fact_encounters   : one row per encounter
--   fact_conditions   : one row per (patient, condition, onset date)
--   fact_medications  : one row per medication order
--   fact_procedures   : one row per procedure performed
--   fact_observations : one row per recorded observation (vital/lab/survey)
-- ============================================================================

USE healthcare_analytics;

DROP TABLE IF EXISTS fact_observations;
DROP TABLE IF EXISTS fact_procedures;
DROP TABLE IF EXISTS fact_medications;
DROP TABLE IF EXISTS fact_conditions;
DROP TABLE IF EXISTS fact_encounters;
DROP TABLE IF EXISTS dim_provider;
DROP TABLE IF EXISTS dim_organization;
DROP TABLE IF EXISTS dim_patient;
DROP TABLE IF EXISTS dim_date;

-- ---------------------------------------------------------------------------
-- dim_date  -- standard calendar dimension, populated in 04_load_dimensions
-- ---------------------------------------------------------------------------
CREATE TABLE dim_date (
    date_key      INT           NOT NULL,  -- YYYYMMDD
    full_date     DATE          NOT NULL,
    day_of_month  TINYINT       NOT NULL,
    day_name      VARCHAR(10)   NOT NULL,
    is_weekend    TINYINT(1)    NOT NULL,
    month_num     TINYINT       NOT NULL,
    month_name    VARCHAR(10)   NOT NULL,
    quarter_num   TINYINT       NOT NULL,
    year_num      SMALLINT      NOT NULL,
    PRIMARY KEY (date_key)
);

-- ---------------------------------------------------------------------------
-- dim_patient  -- Type 2 SCD.
--
-- Synthea gives us one snapshot per patient, so the first load seeds exactly
-- one "version 1, currently open" row per patient. The columns are here so
-- that if you re-export Synthea later (or hand-edit a demographic change)
-- and re-run a Type 2 merge, dim_patient will actually accumulate history --
-- that's the point of designing it this way now instead of waiting until
-- there's a second snapshot to justify it.
-- ---------------------------------------------------------------------------
CREATE TABLE dim_patient (
    patient_key           INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    patient_id            CHAR(36)      NOT NULL,   -- Synthea's natural key
    first_name            VARCHAR(100)  NULL,
    last_name             VARCHAR(100)  NULL,
    gender                VARCHAR(5)    NULL,
    race                  VARCHAR(50)   NULL,
    ethnicity             VARCHAR(50)   NULL,
    marital_status        VARCHAR(5)    NULL,
    birth_date            DATE          NULL,
    death_date            DATE          NULL,
    city                  VARCHAR(100)  NULL,
    state                 VARCHAR(100)  NULL,
    zip                   VARCHAR(20)   NULL,
    effective_start_date  DATE          NOT NULL,
    effective_end_date    DATE          NULL,       -- NULL = currently open
    is_current            TINYINT(1)    NOT NULL DEFAULT 1,
    PRIMARY KEY (patient_key),
    INDEX ix_dim_patient_natural (patient_id, is_current)
);

-- ---------------------------------------------------------------------------
-- dim_organization / dim_provider  -- Type 1 (overwrite), no history needed
-- for a facility or a provider's home org in this project's scope.
-- ---------------------------------------------------------------------------
CREATE TABLE dim_organization (
    organization_key  INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    organization_id   CHAR(36)      NOT NULL,
    name              VARCHAR(200)  NULL,
    city              VARCHAR(100)  NULL,
    state             VARCHAR(100)  NULL,
    zip               VARCHAR(20)   NULL,
    PRIMARY KEY (organization_key),
    UNIQUE KEY uq_dim_org_natural (organization_id)
);

CREATE TABLE dim_provider (
    provider_key      INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    provider_id       CHAR(36)      NOT NULL,
    organization_key  INT UNSIGNED  NULL,
    name              VARCHAR(150)  NULL,
    gender            VARCHAR(5)    NULL,
    speciality        VARCHAR(100)  NULL,
    city              VARCHAR(100)  NULL,
    state             VARCHAR(100)  NULL,
    PRIMARY KEY (provider_key),
    UNIQUE KEY uq_dim_provider_natural (provider_id),
    CONSTRAINT fk_provider_org FOREIGN KEY (organization_key) REFERENCES dim_organization (organization_key)
);

-- ---------------------------------------------------------------------------
-- fact_encounters
-- Grain: one row per encounter. encounter_id is kept as a degenerate
-- dimension (Day 10 concept) -- it's a transaction identifier that doesn't
-- need its own dimension table, so it lives directly on the fact.
-- ---------------------------------------------------------------------------
CREATE TABLE fact_encounters (
    encounter_key         INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    encounter_id          CHAR(36)      NOT NULL,   -- degenerate dimension
    patient_key           INT UNSIGNED  NOT NULL,
    provider_key          INT UNSIGNED  NULL,
    organization_key      INT UNSIGNED  NULL,
    start_date_key        INT           NOT NULL,
    stop_date_key         INT           NULL,
    encounter_class       VARCHAR(30)   NULL,
    code                  VARCHAR(20)   NULL,
    description           VARCHAR(255)  NULL,
    length_of_stay_hours  DECIMAL(10,2) NULL,        -- additive measure
    base_encounter_cost   DECIMAL(14,2) NULL,        -- additive measure
    total_claim_cost      DECIMAL(14,2) NULL,        -- additive measure
    payer_coverage        DECIMAL(14,2) NULL,        -- additive measure
    reason_code           VARCHAR(20)   NULL,
    reason_description    VARCHAR(255)  NULL,
    PRIMARY KEY (encounter_key),
    UNIQUE KEY uq_fact_enc_natural (encounter_id),
    CONSTRAINT fk_enc_patient  FOREIGN KEY (patient_key)      REFERENCES dim_patient (patient_key),
    CONSTRAINT fk_enc_provider FOREIGN KEY (provider_key)     REFERENCES dim_provider (provider_key),
    CONSTRAINT fk_enc_org      FOREIGN KEY (organization_key) REFERENCES dim_organization (organization_key),
    CONSTRAINT fk_enc_start_dt FOREIGN KEY (start_date_key)   REFERENCES dim_date (date_key)
);

-- ---------------------------------------------------------------------------
-- fact_conditions
-- Grain: one row per condition diagnosed per patient per encounter.
-- No cost/quantity measure -- this is a "factless fact" (existence of an
-- event), which is fine; not every fact table needs a numeric measure.
-- ---------------------------------------------------------------------------
CREATE TABLE fact_conditions (
    condition_key   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    patient_key     INT UNSIGNED  NOT NULL,
    encounter_key   INT UNSIGNED  NULL,
    onset_date_key  INT           NOT NULL,
    resolved_date_key INT         NULL,
    code            VARCHAR(20)   NULL,  -- SNOMED-CT by Synthea convention; this export doesn't label it per-row
    description     VARCHAR(255)  NULL,
    PRIMARY KEY (condition_key),
    CONSTRAINT fk_cond_patient FOREIGN KEY (patient_key)   REFERENCES dim_patient (patient_key),
    CONSTRAINT fk_cond_enc     FOREIGN KEY (encounter_key) REFERENCES fact_encounters (encounter_key),
    CONSTRAINT fk_cond_onset   FOREIGN KEY (onset_date_key) REFERENCES dim_date (date_key)
);

-- ---------------------------------------------------------------------------
-- fact_medications
-- Grain: one row per medication order.
-- ---------------------------------------------------------------------------
CREATE TABLE fact_medications (
    medication_key   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    patient_key      INT UNSIGNED  NOT NULL,
    encounter_key    INT UNSIGNED  NULL,
    start_date_key   INT           NOT NULL,
    stop_date_key    INT           NULL,
    code             VARCHAR(20)   NULL,
    description      VARCHAR(255)  NULL,
    dispenses        INT           NULL,             -- additive measure
    base_cost        DECIMAL(14,2) NULL,              -- additive measure
    total_cost       DECIMAL(14,2) NULL,              -- additive measure
    payer_coverage   DECIMAL(14,2) NULL,              -- additive measure
    PRIMARY KEY (medication_key),
    CONSTRAINT fk_med_patient FOREIGN KEY (patient_key)    REFERENCES dim_patient (patient_key),
    CONSTRAINT fk_med_enc     FOREIGN KEY (encounter_key)  REFERENCES fact_encounters (encounter_key),
    CONSTRAINT fk_med_start   FOREIGN KEY (start_date_key) REFERENCES dim_date (date_key)
);

-- ---------------------------------------------------------------------------
-- fact_procedures
-- Grain: one row per procedure performed.
-- ---------------------------------------------------------------------------
CREATE TABLE fact_procedures (
    procedure_key   INT UNSIGNED  NOT NULL AUTO_INCREMENT,
    patient_key     INT UNSIGNED  NOT NULL,
    encounter_key   INT UNSIGNED  NULL,
    date_key        INT           NOT NULL,
    code            VARCHAR(20)   NULL,  -- SNOMED-CT by Synthea convention; this export doesn't label it per-row
    description     VARCHAR(255)  NULL,
    base_cost       DECIMAL(14,2) NULL,               -- additive measure
    PRIMARY KEY (procedure_key),
    CONSTRAINT fk_proc_patient FOREIGN KEY (patient_key)   REFERENCES dim_patient (patient_key),
    CONSTRAINT fk_proc_enc     FOREIGN KEY (encounter_key) REFERENCES fact_encounters (encounter_key),
    CONSTRAINT fk_proc_date    FOREIGN KEY (date_key)      REFERENCES dim_date (date_key)
);

-- ---------------------------------------------------------------------------
-- fact_observations
-- Grain: one row per observation. VALUE is split into value_numeric /
-- value_text based on Synthea's TYPE column -- a numeric vital (heart rate)
-- and a text survey answer can't share one typed column without forcing
-- ugly casts on every query, so we pay the cleanup cost once here.
-- Non-additive: an observation is a point-in-time reading, not something
-- you'd ever sum (summing heart rate readings is meaningless).
-- ---------------------------------------------------------------------------
CREATE TABLE fact_observations (
    observation_key  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    patient_key      INT UNSIGNED    NOT NULL,
    encounter_key    INT UNSIGNED    NULL,
    date_key         INT             NOT NULL,
    category         VARCHAR(50)     NULL,
    code             VARCHAR(20)     NULL,
    description      VARCHAR(255)    NULL,
    value_numeric    DECIMAL(14,4)   NULL,
    value_text       VARCHAR(255)    NULL,
    units            VARCHAR(50)     NULL,
    PRIMARY KEY (observation_key),
    CONSTRAINT fk_obs_patient FOREIGN KEY (patient_key)   REFERENCES dim_patient (patient_key),
    CONSTRAINT fk_obs_enc     FOREIGN KEY (encounter_key) REFERENCES fact_encounters (encounter_key),
    CONSTRAINT fk_obs_date    FOREIGN KEY (date_key)      REFERENCES dim_date (date_key)
);

ALTER TABLE fact_conditions   ADD INDEX ix_fact_cond_patient (patient_key);
ALTER TABLE fact_medications  ADD INDEX ix_fact_med_patient (patient_key);
ALTER TABLE fact_procedures   ADD INDEX ix_fact_proc_patient (patient_key);
ALTER TABLE fact_observations ADD INDEX ix_fact_obs_patient (patient_key), ADD INDEX ix_fact_obs_code (code);
