-- ============================================================================
-- healthcare-data-analytics : 02_load_staging.sql
--
-- Loads the Synthea CSV exports into the staging tables from 01.
--
-- BEFORE RUNNING:
--   1. Generate or download Synthea CSV output (see README.md "Getting the
--      data"). You should end up with a folder containing patients.csv,
--      encounters.csv, conditions.csv, medications.csv, procedures.csv,
--      observations.csv, organizations.csv, providers.csv.
--   2. Replace every '/path/to/synthea/csv/' below with the actual folder
--      path on your machine. On Windows, use forward slashes even in
--      MySQL Workbench, e.g. 'C:/Users/you/synthea/output/csv/patients.csv'.
--   3. Open each CSV's header row once and compare it against the column
--      list in the LOAD DATA statement below -- Synthea has changed CSV
--      columns across versions. If yours differs, edit the column list
--      (not the staging table) to match.
--   4. If you get "Loading local data is disabled", run once:
--        SET GLOBAL local_infile = 1;
--      and make sure Workbench's connection has "Allow loading local infile"
--      checked (Edit Connection > Advanced), then reconnect.
-- ============================================================================

USE healthcare_analytics;

-- ---------------------------------------------------------------------------
-- patients
-- ---------------------------------------------------------------------------
LOAD DATA LOCAL INFILE '/path/to/synthea/csv/patients.csv'
INTO TABLE stg_patients
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(id, @birthdate, @deathdate, ssn, drivers, passport, prefix, first_name, last_name,
 suffix, maiden, marital, race, ethnicity, gender, birthplace, address, city, state,
 county, fips, zip, @lat, @lon, @healthcare_expenses, @healthcare_coverage, @income)
SET
    birthdate           = NULLIF(@birthdate, ''),
    deathdate           = NULLIF(@deathdate, ''),
    lat                 = NULLIF(@lat, ''),
    lon                 = NULLIF(@lon, ''),
    healthcare_expenses = NULLIF(@healthcare_expenses, ''),
    healthcare_coverage = NULLIF(@healthcare_coverage, ''),
    income              = NULLIF(@income, '');

-- ---------------------------------------------------------------------------
-- organizations
-- ---------------------------------------------------------------------------
LOAD DATA LOCAL INFILE '/path/to/synthea/csv/organizations.csv'
INTO TABLE stg_organizations
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(id, name, address, city, state, zip, @lat, @lon, phone, @revenue, @utilization)
SET
    lat         = NULLIF(@lat, ''),
    lon         = NULLIF(@lon, ''),
    revenue     = NULLIF(@revenue, ''),
    utilization = NULLIF(@utilization, '');

-- ---------------------------------------------------------------------------
-- providers
-- ---------------------------------------------------------------------------
LOAD DATA LOCAL INFILE '/path/to/synthea/csv/providers.csv'
INTO TABLE stg_providers
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(id, organization, name, gender, speciality, address, city, state, zip, @lat, @lon, @utilization)
SET
    lat         = NULLIF(@lat, ''),
    lon         = NULLIF(@lon, ''),
    utilization = NULLIF(@utilization, '');

-- ---------------------------------------------------------------------------
-- encounters  (timestamps arrive as ISO-8601 with a trailing Z, e.g.
-- 2013-05-24T09:11:31Z -- strip the T/Z so STR_TO_DATE can parse them)
-- ---------------------------------------------------------------------------
LOAD DATA LOCAL INFILE '/path/to/synthea/csv/encounters.csv'
INTO TABLE stg_encounters
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(id, @start_ts, @stop_ts, patient, organization, provider, payer, encounterclass, code,
 description, @base_cost, @total_cost, @payer_coverage, reasoncode, reasondescription)
SET
    start_ts            = STR_TO_DATE(REPLACE(REPLACE(@start_ts, 'T', ' '), 'Z', ''), '%Y-%m-%d %H:%i:%s'),
    stop_ts             = STR_TO_DATE(REPLACE(REPLACE(@stop_ts, 'T', ' '), 'Z', ''), '%Y-%m-%d %H:%i:%s'),
    base_encounter_cost = NULLIF(@base_cost, ''),
    total_claim_cost    = NULLIF(@total_cost, ''),
    payer_coverage      = NULLIF(@payer_coverage, '');

-- ---------------------------------------------------------------------------
-- conditions
-- ---------------------------------------------------------------------------
LOAD DATA LOCAL INFILE '/path/to/synthea/csv/conditions.csv'
INTO TABLE stg_conditions
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@start_dt, @stop_dt, patient, encounter, code_system, code, description)
SET
    start_dt = NULLIF(@start_dt, ''),
    stop_dt  = NULLIF(@stop_dt, '');

-- ---------------------------------------------------------------------------
-- medications
-- ---------------------------------------------------------------------------
LOAD DATA LOCAL INFILE '/path/to/synthea/csv/medications.csv'
INTO TABLE stg_medications
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@start_dt, @stop_dt, patient, payer, encounter, code, description, @base_cost,
 @payer_coverage, @dispenses, @totalcost, reasoncode, reasondescription)
SET
    start_dt       = STR_TO_DATE(REPLACE(REPLACE(@start_dt, 'T', ' '), 'Z', ''), '%Y-%m-%d %H:%i:%s'),
    stop_dt        = STR_TO_DATE(REPLACE(REPLACE(@stop_dt, 'T', ' '), 'Z', ''), '%Y-%m-%d %H:%i:%s'),
    base_cost      = NULLIF(@base_cost, ''),
    payer_coverage = NULLIF(@payer_coverage, ''),
    dispenses      = NULLIF(@dispenses, ''),
    totalcost      = NULLIF(@totalcost, '');

-- ---------------------------------------------------------------------------
-- procedures
-- ---------------------------------------------------------------------------
LOAD DATA LOCAL INFILE '/path/to/synthea/csv/procedures.csv'
INTO TABLE stg_procedures
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@start_ts, @stop_ts, patient, encounter, code_system, code, description, @base_cost,
 reasoncode, reasondescription)
SET
    start_ts  = STR_TO_DATE(REPLACE(REPLACE(@start_ts, 'T', ' '), 'Z', ''), '%Y-%m-%d %H:%i:%s'),
    stop_ts   = STR_TO_DATE(REPLACE(REPLACE(@stop_ts, 'T', ' '), 'Z', ''), '%Y-%m-%d %H:%i:%s'),
    base_cost = NULLIF(@base_cost, '');

-- ---------------------------------------------------------------------------
-- observations
-- ---------------------------------------------------------------------------
LOAD DATA LOCAL INFILE '/path/to/synthea/csv/observations.csv'
INTO TABLE stg_observations
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(@obs_date, patient, encounter, category, code, description, value, units, obs_type)
SET
    obs_date = STR_TO_DATE(REPLACE(REPLACE(@obs_date, 'T', ' '), 'Z', ''), '%Y-%m-%d %H:%i:%s');

-- ---------------------------------------------------------------------------
-- Sanity check: row counts should be nonzero and roughly in line with the
-- patient count you generated.
-- ---------------------------------------------------------------------------
SELECT 'stg_patients' AS tbl, COUNT(*) AS rows_loaded FROM stg_patients
UNION ALL SELECT 'stg_organizations', COUNT(*) FROM stg_organizations
UNION ALL SELECT 'stg_providers', COUNT(*) FROM stg_providers
UNION ALL SELECT 'stg_encounters', COUNT(*) FROM stg_encounters
UNION ALL SELECT 'stg_conditions', COUNT(*) FROM stg_conditions
UNION ALL SELECT 'stg_medications', COUNT(*) FROM stg_medications
UNION ALL SELECT 'stg_procedures', COUNT(*) FROM stg_procedures
UNION ALL SELECT 'stg_observations', COUNT(*) FROM stg_observations;
