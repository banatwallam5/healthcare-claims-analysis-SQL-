-- ============================================================================
-- healthcare-data-analytics : 01_staging_schema.sql
-- Raw staging tables that mirror Synthea's CSV export columns 1:1.
-- Nothing is cleaned or typed strictly here on purpose -- this layer exists
-- so a bad row in the source file can't break the load. Cleaning/typing
-- happens in the SET clauses of the LOAD DATA statements below and again
-- when we populate the star schema in 03/04.
--
-- Covers 8 of Synthea's ~18 CSV exports: patients, encounters, conditions,
-- medications, procedures, observations, organizations, providers.
-- (immunizations / allergies / careplans / devices / imaging_studies /
-- supplies / payers / payer_transitions are left for a v2 extension.)
-- ============================================================================

CREATE DATABASE IF NOT EXISTS healthcare_analytics;
USE healthcare_analytics;

DROP TABLE IF EXISTS stg_observations;
DROP TABLE IF EXISTS stg_procedures;
DROP TABLE IF EXISTS stg_medications;
DROP TABLE IF EXISTS stg_conditions;
DROP TABLE IF EXISTS stg_encounters;
DROP TABLE IF EXISTS stg_providers;
DROP TABLE IF EXISTS stg_organizations;
DROP TABLE IF EXISTS stg_patients;

-- ---------------------------------------------------------------------------
-- patients.csv
-- ---------------------------------------------------------------------------
CREATE TABLE stg_patients (
    id                    CHAR(36)      NOT NULL,
    birthdate             DATE          NULL,
    deathdate             DATE          NULL,
    ssn                   VARCHAR(20)   NULL,
    drivers               VARCHAR(20)   NULL,
    passport              VARCHAR(20)   NULL,
    prefix                VARCHAR(10)   NULL,
    first_name            VARCHAR(100)  NULL,
    last_name             VARCHAR(100)  NULL,
    suffix                VARCHAR(10)   NULL,
    maiden                VARCHAR(100)  NULL,
    marital               VARCHAR(5)    NULL,
    race                  VARCHAR(50)   NULL,
    ethnicity             VARCHAR(50)   NULL,
    gender                VARCHAR(5)    NULL,
    birthplace            VARCHAR(150)  NULL,
    address               VARCHAR(150)  NULL,
    city                  VARCHAR(100)  NULL,
    state                 VARCHAR(100)  NULL,
    county                VARCHAR(100)  NULL,
    zip                   VARCHAR(20)   NULL,
    lat                   DECIMAL(10,6) NULL,
    lon                   DECIMAL(10,6) NULL,
    healthcare_expenses   DECIMAL(14,2) NULL,
    healthcare_coverage   DECIMAL(14,2) NULL,
    PRIMARY KEY (id)
);
-- Note: this table intentionally has no FIPS or INCOME column -- the
-- 2019-2021 "1K Sample" CSV export doesn't include them (later Synthea
-- versions added both). If you're loading a newer export that does have
-- them, add the columns back and extend the LOAD DATA statement in 02.

-- ---------------------------------------------------------------------------
-- organizations.csv
-- ---------------------------------------------------------------------------
CREATE TABLE stg_organizations (
    id          CHAR(36)      NOT NULL,
    name        VARCHAR(200)  NULL,
    address     VARCHAR(150)  NULL,
    city        VARCHAR(100)  NULL,
    state       VARCHAR(100)  NULL,
    zip         VARCHAR(20)   NULL,
    lat         DECIMAL(10,6) NULL,
    lon         DECIMAL(10,6) NULL,
    phone       VARCHAR(30)   NULL,
    revenue     DECIMAL(14,2) NULL,
    utilization INT           NULL,
    PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- providers.csv
-- ---------------------------------------------------------------------------
CREATE TABLE stg_providers (
    id             CHAR(36)      NOT NULL,
    organization   CHAR(36)      NULL,
    name           VARCHAR(150)  NULL,
    gender         VARCHAR(5)    NULL,
    speciality     VARCHAR(100)  NULL,
    address        VARCHAR(150)  NULL,
    city           VARCHAR(100)  NULL,
    state          VARCHAR(100)  NULL,
    zip            VARCHAR(20)   NULL,
    lat            DECIMAL(10,6) NULL,
    lon            DECIMAL(10,6) NULL,
    utilization    INT           NULL,
    PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- encounters.csv
-- ---------------------------------------------------------------------------
CREATE TABLE stg_encounters (
    id                   CHAR(36)      NOT NULL,
    start_ts             DATETIME      NULL,
    stop_ts              DATETIME      NULL,
    patient              CHAR(36)      NULL,
    organization         CHAR(36)      NULL,
    provider             CHAR(36)      NULL,
    payer                CHAR(36)      NULL,
    encounterclass       VARCHAR(30)   NULL,
    code                 VARCHAR(20)   NULL,
    description          VARCHAR(255)  NULL,
    base_encounter_cost  DECIMAL(14,2) NULL,
    total_claim_cost     DECIMAL(14,2) NULL,
    payer_coverage       DECIMAL(14,2) NULL,
    reasoncode           VARCHAR(20)   NULL,
    reasondescription    VARCHAR(255)  NULL,
    PRIMARY KEY (id)
);

-- ---------------------------------------------------------------------------
-- conditions.csv  (no natural single-column PK -- composite)
-- Note: no SYSTEM/code_system column in this export version (Synthea's
-- older CSV exporter didn't emit it -- conditions are SNOMED-CT by
-- convention, it's just not labeled per-row in this file).
-- ---------------------------------------------------------------------------
CREATE TABLE stg_conditions (
    start_dt      DATE          NULL,
    stop_dt       DATE          NULL,
    patient       CHAR(36)      NULL,
    encounter     CHAR(36)      NULL,
    code          VARCHAR(20)   NULL,
    description   VARCHAR(255)  NULL
);

-- ---------------------------------------------------------------------------
-- medications.csv
-- ---------------------------------------------------------------------------
CREATE TABLE stg_medications (
    start_dt            DATETIME      NULL,
    stop_dt             DATETIME      NULL,
    patient             CHAR(36)      NULL,
    payer               CHAR(36)      NULL,
    encounter           CHAR(36)      NULL,
    code                VARCHAR(20)   NULL,
    description         VARCHAR(255)  NULL,
    base_cost           DECIMAL(14,2) NULL,
    payer_coverage      DECIMAL(14,2) NULL,
    dispenses            INT          NULL,
    totalcost             DECIMAL(14,2) NULL,
    reasoncode            VARCHAR(20)  NULL,
    reasondescription      VARCHAR(255) NULL
);

-- ---------------------------------------------------------------------------
-- procedures.csv  (same note as conditions -- no SYSTEM column here)
-- ---------------------------------------------------------------------------
CREATE TABLE stg_procedures (
    start_ts       DATETIME      NULL,
    stop_ts        DATETIME      NULL,
    patient        CHAR(36)      NULL,
    encounter      CHAR(36)      NULL,
    code           VARCHAR(20)   NULL,
    description    VARCHAR(255)  NULL,
    base_cost      DECIMAL(14,2) NULL,
    reasoncode     VARCHAR(20)   NULL,
    reasondescription VARCHAR(255) NULL
);

-- ---------------------------------------------------------------------------
-- observations.csv  (VALUE is mixed numeric/text -- kept as text here,
-- split into numeric/text columns when loaded into the fact table)
-- ---------------------------------------------------------------------------
CREATE TABLE stg_observations (
    obs_date      DATETIME      NULL,
    patient       CHAR(36)      NULL,
    encounter     CHAR(36)      NULL,
    category      VARCHAR(50)   NULL,
    code          VARCHAR(20)   NULL,
    description   VARCHAR(255)  NULL,
    value         VARCHAR(255)  NULL,
    units         VARCHAR(50)   NULL,
    obs_type      VARCHAR(20)   NULL
);

-- Helpful indexes for the joins we'll do when populating facts
ALTER TABLE stg_encounters   ADD INDEX ix_stg_enc_patient (patient), ADD INDEX ix_stg_enc_provider (provider), ADD INDEX ix_stg_enc_org (organization);
ALTER TABLE stg_conditions   ADD INDEX ix_stg_cond_patient (patient), ADD INDEX ix_stg_cond_enc (encounter);
ALTER TABLE stg_medications  ADD INDEX ix_stg_med_patient (patient), ADD INDEX ix_stg_med_enc (encounter);
ALTER TABLE stg_procedures   ADD INDEX ix_stg_proc_patient (patient), ADD INDEX ix_stg_proc_enc (encounter);
ALTER TABLE stg_observations ADD INDEX ix_stg_obs_patient (patient), ADD INDEX ix_stg_obs_enc (encounter);
ALTER TABLE stg_providers    ADD INDEX ix_stg_prov_org (organization);
