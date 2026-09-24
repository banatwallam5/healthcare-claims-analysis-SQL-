-- ============================================================================
-- healthcare-data-analytics : 07_simulate_scd_change.sql
--
-- One-time, deliberate simulation -- NOT part of the normal 01-06 pipeline.
--
-- Why this exists: dim_patient is designed as a real Type 2 SCD (see
-- 03_star_schema.sql), but the Synthea export is a single point-in-time
-- snapshot -- every patient gets exactly one "version 1, open" row on first
-- load, so there's no real history yet to demonstrate an as-of query
-- against (Q9 in 06_analysis_queries.sql). This script manufactures that
-- history for a handful of patients by hand, the same way a real Type 2
-- merge would when it detects a changed attribute on a second data load --
-- so the as-of query in 06 has something real to distinguish between.
--
-- RUN ONCE. This is a mutation, not a read-only analysis query -- running it
-- a second time will try to close out an already-closed-out row and won't
-- do what you expect. If you need to reset dim_patient back to a clean
-- single-version state, re-run 03_star_schema.sql (drops/recreates the
-- table) followed by 04_load_dimensions.sql and 05_load_facts.sql.
--
-- Design decisions:
--   - Simulated 5 patients, not 1 -- picked as the 5 with the highest
--     encounter_count in fact_encounters, so the demo uses patients who
--     already show up elsewhere in this project's results rather than
--     arbitrary/thin records.
--   - Changed attribute: marital_status. Picked over an address/city/state
--     change because it's a single self-contained column -- a fake
--     city/state/zip combination risks looking inconsistent (e.g. a zip
--     that doesn't match the city), where flipping M <-> S needs no
--     supporting data to stay internally consistent.
--   - New version's effective_start_date is fixed at 2023-06-01 for all 5
--     patients -- arbitrary but deliberately picked to sit well after every
--     patient's birth_date (their v1 effective_start_date) and before
--     "today," so an as-of query using an older date returns the original
--     row and one using a recent date returns the new one.
-- ============================================================================

USE healthcare_analytics;

SET @change_date = '2023-06-01';

-- ---------------------------------------------------------------------------
-- Step 1: identify the 5 patients to simulate a change for -- the 5 with
-- the most encounters on file.
-- ---------------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS tmp_scd_demo_patients;
CREATE TEMPORARY TABLE tmp_scd_demo_patients AS
SELECT dp.patient_id
FROM dim_patient dp
JOIN fact_encounters fe ON fe.patient_key = dp.patient_key
WHERE dp.is_current = 1
GROUP BY dp.patient_id
ORDER BY COUNT(*) DESC
LIMIT 5;

-- ---------------------------------------------------------------------------
-- Step 2: close out their current ("version 1") row.
-- ---------------------------------------------------------------------------
UPDATE dim_patient
SET effective_end_date = DATE_SUB(@change_date, INTERVAL 1 DAY),
    is_current = 0
WHERE patient_id IN (SELECT patient_id FROM tmp_scd_demo_patients)
  AND is_current = 1;

-- ---------------------------------------------------------------------------
-- Step 3: insert their "version 2" row -- same demographic info, except
-- marital_status flipped (M <-> S; NULL treated as becoming 'S').
-- ---------------------------------------------------------------------------
INSERT INTO dim_patient (
    patient_id, first_name, last_name, gender, race, ethnicity, marital_status,
    birth_date, death_date, city, state, zip,
    effective_start_date, effective_end_date, is_current
)
SELECT
    old.patient_id,
    old.first_name,
    old.last_name,
    old.gender,
    old.race,
    old.ethnicity,
    CASE old.marital_status WHEN 'M' THEN 'S' WHEN 'S' THEN 'M' ELSE 'S' END,
    old.birth_date,
    old.death_date,
    old.city,
    old.state,
    old.zip,
    @change_date,
    NULL,
    1
FROM dim_patient old
JOIN tmp_scd_demo_patients demo ON demo.patient_id = old.patient_id
WHERE old.is_current = 0
  AND old.effective_end_date = DATE_SUB(@change_date, INTERVAL 1 DAY);

DROP TEMPORARY TABLE IF EXISTS tmp_scd_demo_patients;

-- ---------------------------------------------------------------------------
-- Sanity check: each of the 5 patients should now show exactly 2 rows --
-- one closed-out (is_current = 0) with the original marital_status, one
-- open (is_current = 1) with it flipped.
-- ---------------------------------------------------------------------------
SELECT patient_id, first_name, last_name, marital_status,
       effective_start_date, effective_end_date, is_current
FROM dim_patient
WHERE patient_id IN (
    SELECT patient_id FROM dim_patient GROUP BY patient_id HAVING COUNT(*) > 1
)
ORDER BY patient_id, effective_start_date;
