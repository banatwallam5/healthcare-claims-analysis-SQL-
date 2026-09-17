-- ============================================================================
-- healthcare-data-analytics : 05_load_facts.sql
-- Populates the fact tables by joining staging rows to dimension surrogate
-- keys. Run after 01-04.
-- ============================================================================

USE healthcare_analytics;

-- ---------------------------------------------------------------------------
-- fact_encounters
-- ---------------------------------------------------------------------------
INSERT INTO fact_encounters (
    encounter_id, patient_key, provider_key, organization_key,
    start_date_key, stop_date_key, encounter_class, code, description,
    length_of_stay_hours, base_encounter_cost, total_claim_cost, payer_coverage,
    reason_code, reason_description
)
SELECT
    e.id,
    dp.patient_key,
    dpr.provider_key,
    do_.organization_key,
    CAST(DATE_FORMAT(e.start_ts, '%Y%m%d') AS UNSIGNED),
    CAST(DATE_FORMAT(e.stop_ts, '%Y%m%d') AS UNSIGNED),
    e.encounterclass,
    e.code,
    e.description,
    TIMESTAMPDIFF(MINUTE, e.start_ts, e.stop_ts) / 60.0,
    e.base_encounter_cost,
    e.total_claim_cost,
    e.payer_coverage,
    e.reasoncode,
    e.reasondescription
FROM stg_encounters e
JOIN dim_patient dp        ON dp.patient_id = e.patient AND dp.is_current = 1
LEFT JOIN dim_provider dpr ON dpr.provider_id = e.provider
LEFT JOIN dim_organization do_ ON do_.organization_id = e.organization;

-- ---------------------------------------------------------------------------
-- fact_conditions
-- ---------------------------------------------------------------------------
INSERT INTO fact_conditions (
    patient_key, encounter_key, onset_date_key, resolved_date_key,
    code_system, code, description
)
SELECT
    dp.patient_key,
    fe.encounter_key,
    CAST(DATE_FORMAT(c.start_dt, '%Y%m%d') AS UNSIGNED),
    CASE WHEN c.stop_dt IS NULL THEN NULL ELSE CAST(DATE_FORMAT(c.stop_dt, '%Y%m%d') AS UNSIGNED) END,
    c.code_system,
    c.code,
    c.description
FROM stg_conditions c
JOIN dim_patient dp     ON dp.patient_id = c.patient AND dp.is_current = 1
LEFT JOIN fact_encounters fe ON fe.encounter_id = c.encounter;

-- ---------------------------------------------------------------------------
-- fact_medications
-- ---------------------------------------------------------------------------
INSERT INTO fact_medications (
    patient_key, encounter_key, start_date_key, stop_date_key,
    code, description, dispenses, base_cost, total_cost, payer_coverage
)
SELECT
    dp.patient_key,
    fe.encounter_key,
    CAST(DATE_FORMAT(m.start_dt, '%Y%m%d') AS UNSIGNED),
    CASE WHEN m.stop_dt IS NULL THEN NULL ELSE CAST(DATE_FORMAT(m.stop_dt, '%Y%m%d') AS UNSIGNED) END,
    m.code,
    m.description,
    m.dispenses,
    m.base_cost,
    m.totalcost,
    m.payer_coverage
FROM stg_medications m
JOIN dim_patient dp     ON dp.patient_id = m.patient AND dp.is_current = 1
LEFT JOIN fact_encounters fe ON fe.encounter_id = m.encounter;

-- ---------------------------------------------------------------------------
-- fact_procedures
-- ---------------------------------------------------------------------------
INSERT INTO fact_procedures (
    patient_key, encounter_key, date_key, code_system, code, description, base_cost
)
SELECT
    dp.patient_key,
    fe.encounter_key,
    CAST(DATE_FORMAT(p.start_ts, '%Y%m%d') AS UNSIGNED),
    p.code_system,
    p.code,
    p.description,
    p.base_cost
FROM stg_procedures p
JOIN dim_patient dp     ON dp.patient_id = p.patient AND dp.is_current = 1
LEFT JOIN fact_encounters fe ON fe.encounter_id = p.encounter;

-- ---------------------------------------------------------------------------
-- fact_observations
-- value_numeric / value_text split based on Synthea's TYPE column
-- ('numeric' vs. 'text'/other).
-- ---------------------------------------------------------------------------
INSERT INTO fact_observations (
    patient_key, encounter_key, date_key, category, code, description,
    value_numeric, value_text, units
)
SELECT
    dp.patient_key,
    fe.encounter_key,
    CAST(DATE_FORMAT(o.obs_date, '%Y%m%d') AS UNSIGNED),
    o.category,
    o.code,
    o.description,
    CASE WHEN o.obs_type = 'numeric' THEN CAST(o.value AS DECIMAL(14,4)) ELSE NULL END,
    CASE WHEN o.obs_type = 'numeric' THEN NULL ELSE o.value END,
    o.units
FROM stg_observations o
JOIN dim_patient dp     ON dp.patient_id = o.patient AND dp.is_current = 1
LEFT JOIN fact_encounters fe ON fe.encounter_id = o.encounter;

-- Sanity check
SELECT 'fact_encounters' AS tbl, COUNT(*) FROM fact_encounters
UNION ALL SELECT 'fact_conditions', COUNT(*) FROM fact_conditions
UNION ALL SELECT 'fact_medications', COUNT(*) FROM fact_medications
UNION ALL SELECT 'fact_procedures', COUNT(*) FROM fact_procedures
UNION ALL SELECT 'fact_observations', COUNT(*) FROM fact_observations;
