-- ============================================================================
-- healthcare-data-analytics : 04_load_dimensions.sql
-- Populates dim_date, dim_organization, dim_provider, dim_patient from
-- the staging tables. Run after 01-03.
-- ============================================================================

USE healthcare_analytics;

-- ---------------------------------------------------------------------------
-- dim_date: generate every calendar day spanning your data, plus a small
-- buffer. Adjust the two dates below to comfortably cover your earliest
-- encounter start and latest encounter stop (check with:
--   SELECT MIN(start_ts), MAX(stop_ts) FROM stg_encounters;
-- Synthea backdates patient histories for decades, so this range is
-- intentionally wide -- narrow it if it makes the table unwieldy.
-- ---------------------------------------------------------------------------
SET @start_date = '1920-01-01';
SET @end_date   = '2026-12-31';

INSERT INTO dim_date (date_key, full_date, day_of_month, day_name, is_weekend,
                       month_num, month_name, quarter_num, year_num)
WITH RECURSIVE date_seq AS (
    SELECT @start_date AS full_date
    UNION ALL
    SELECT full_date + INTERVAL 1 DAY
    FROM date_seq
    WHERE full_date + INTERVAL 1 DAY <= @end_date
)
SELECT
    CAST(DATE_FORMAT(full_date, '%Y%m%d') AS UNSIGNED) AS date_key,
    full_date,
    DAY(full_date),
    DAYNAME(full_date),
    IF(DAYOFWEEK(full_date) IN (1, 7), 1, 0),
    MONTH(full_date),
    MONTHNAME(full_date),
    QUARTER(full_date),
    YEAR(full_date)
FROM date_seq;
-- Note: MySQL's default cte_max_recursion_depth (1000) is too low for a
-- multi-decade range. If this errors out, run first:
--   SET SESSION cte_max_recursion_depth = 200000;

-- ---------------------------------------------------------------------------
-- dim_organization
-- ---------------------------------------------------------------------------
INSERT INTO dim_organization (organization_id, name, city, state, zip)
SELECT id, name, city, state, zip
FROM stg_organizations;

-- ---------------------------------------------------------------------------
-- dim_provider
-- ---------------------------------------------------------------------------
INSERT INTO dim_provider (provider_id, organization_key, name, gender, speciality, city, state)
SELECT
    p.id,
    o.organization_key,
    p.name,
    p.gender,
    p.speciality,
    p.city,
    p.state
FROM stg_providers p
LEFT JOIN dim_organization o
    ON o.organization_id = p.organization;

-- ---------------------------------------------------------------------------
-- dim_patient -- Type 2 SCD, first load.
-- Every patient gets exactly one "open" version. effective_start_date uses
-- the patient's birth date (their record has existed, conceptually, since
-- birth); effective_end_date stays NULL and is_current stays 1 until a
-- future re-load detects a changed attribute and closes this row out.
-- ---------------------------------------------------------------------------
INSERT INTO dim_patient (
    patient_id, first_name, last_name, gender, race, ethnicity, marital_status,
    birth_date, death_date, city, state, zip,
    effective_start_date, effective_end_date, is_current
)
SELECT
    id, first_name, last_name, gender, race, ethnicity, marital,
    birthdate, deathdate, city, state, zip,
    birthdate, NULL, 1
FROM stg_patients;

-- Sanity check
SELECT 'dim_date' AS tbl, COUNT(*) FROM dim_date
UNION ALL SELECT 'dim_organization', COUNT(*) FROM dim_organization
UNION ALL SELECT 'dim_provider', COUNT(*) FROM dim_provider
UNION ALL SELECT 'dim_patient', COUNT(*) FROM dim_patient;
