-- ============================================================================
-- healthcare-data-analytics : 06_analysis_queries.sql
--
-- Answers to the first 5 "Planned analysis questions" from the README.
-- These are all read-only SELECT statements -- nothing here creates,
-- drops, or modifies any table, so it's always safe to re-run any of them
-- individually as many times as you like.
--
-- Q6a and Q6b (days since last seen / readmission gap) are both included
-- below, along with Q7 (condition trend pivot), Q8 (anti-join screening
-- gap), and Q9 (as-of query against the Type 2 SCD).
--
-- NOTE on Q9: it depends on sql/07_simulate_scd_change.sql having been run
-- first. Without that, dim_patient has exactly one version per patient and
-- Q9 will return the same row for any date you check -- see that file's
-- header and the comment on Q9 below for why.
-- ============================================================================

USE healthcare_analytics;

-- ---------------------------------------------------------------------------
-- Q1a: Top 10 most common diagnosed conditions overall.
-- "Prevalence" here is measured as the number of DISTINCT patients ever
-- diagnosed with a condition, not the raw row count -- a patient diagnosed
-- with the same condition twice should still only count as 1 for prevalence.
-- diagnosis_count is included alongside it so you can see the difference.
--
-- NOTE (found while reviewing results): Synthea logs social determinants of
-- health (employment status, education, social isolation, etc.) as SNOMED
-- "findings" in this SAME conditions.csv table as real clinical diagnoses --
-- the two are only distinguishable by the "(disorder)" vs. "(finding)"
-- suffix in the description text. Since these aren't real diagnosed medical
-- conditions, they're split into two separate results below rather than
-- lumped together under one "top diagnosed conditions" answer.
-- ---------------------------------------------------------------------------

-- Q1a (disorders only): top 10 real clinical diagnoses
SELECT
    fc.description,
    fc.code,
    COUNT(*)                       AS diagnosis_count,
    COUNT(DISTINCT fc.patient_key) AS patient_count
FROM fact_conditions fc
WHERE fc.description LIKE '%(disorder)%'
GROUP BY fc.code, fc.description
ORDER BY patient_count DESC
LIMIT 10;

-- Q1a (findings/SDOH): top 10 social determinants of health signals
SELECT
    fc.description,
    fc.code,
    COUNT(*)                       AS diagnosis_count,
    COUNT(DISTINCT fc.patient_key) AS patient_count
FROM fact_conditions fc
WHERE fc.description LIKE '%(finding)%'
GROUP BY fc.code, fc.description
ORDER BY patient_count DESC
LIMIT 10;

-- ---------------------------------------------------------------------------
-- Q1b: For those same top 10 lists, break prevalence down by age band (age
-- is computed as of the condition's onset date, not the patient's current
-- age) and gender. Disorders and findings are kept as two separate result
-- sets for the same reason as Q1a above.
-- ---------------------------------------------------------------------------

-- Q1b (disorders only): age band / gender breakdown for the top 10 real diagnoses
WITH top_disorders AS (
    SELECT fc.code, fc.description, COUNT(DISTINCT fc.patient_key) AS patient_count
    FROM fact_conditions fc
    WHERE fc.description LIKE '%(disorder)%'
    GROUP BY fc.code, fc.description
    ORDER BY patient_count DESC
    LIMIT 10
)
SELECT
    tc.description,
    dp.gender,
    CASE
        WHEN TIMESTAMPDIFF(YEAR, dp.birth_date, dd.full_date) < 18            THEN '0-17'
        WHEN TIMESTAMPDIFF(YEAR, dp.birth_date, dd.full_date) BETWEEN 18 AND 34 THEN '18-34'
        WHEN TIMESTAMPDIFF(YEAR, dp.birth_date, dd.full_date) BETWEEN 35 AND 49 THEN '35-49'
        WHEN TIMESTAMPDIFF(YEAR, dp.birth_date, dd.full_date) BETWEEN 50 AND 64 THEN '50-64'
        WHEN TIMESTAMPDIFF(YEAR, dp.birth_date, dd.full_date) BETWEEN 65 AND 79 THEN '65-79'
        ELSE '80+'
    END AS age_band,
    COUNT(DISTINCT fc.patient_key) AS patient_count
FROM fact_conditions fc
JOIN top_disorders tc ON tc.code = fc.code
JOIN dim_patient dp   ON dp.patient_key = fc.patient_key
JOIN dim_date dd      ON dd.date_key    = fc.onset_date_key
GROUP BY tc.description, dp.gender, age_band
ORDER BY tc.description, age_band, dp.gender;

-- Q1b (findings/SDOH): age band / gender breakdown for the top 10 SDOH signals
WITH top_findings AS (
    SELECT fc.code, fc.description, COUNT(DISTINCT fc.patient_key) AS patient_count
    FROM fact_conditions fc
    WHERE fc.description LIKE '%(finding)%'
    GROUP BY fc.code, fc.description
    ORDER BY patient_count DESC
    LIMIT 10
)
SELECT
    tc.description,
    dp.gender,
    CASE
        WHEN TIMESTAMPDIFF(YEAR, dp.birth_date, dd.full_date) < 18            THEN '0-17'
        WHEN TIMESTAMPDIFF(YEAR, dp.birth_date, dd.full_date) BETWEEN 18 AND 34 THEN '18-34'
        WHEN TIMESTAMPDIFF(YEAR, dp.birth_date, dd.full_date) BETWEEN 35 AND 49 THEN '35-49'
        WHEN TIMESTAMPDIFF(YEAR, dp.birth_date, dd.full_date) BETWEEN 50 AND 64 THEN '50-64'
        WHEN TIMESTAMPDIFF(YEAR, dp.birth_date, dd.full_date) BETWEEN 65 AND 79 THEN '65-79'
        ELSE '80+'
    END AS age_band,
    COUNT(DISTINCT fc.patient_key) AS patient_count
FROM fact_conditions fc
JOIN top_findings tc ON tc.code = fc.code
JOIN dim_patient dp  ON dp.patient_key = fc.patient_key
JOIN dim_date dd     ON dd.date_key    = fc.onset_date_key
GROUP BY tc.description, dp.gender, age_band
ORDER BY tc.description, age_band, dp.gender;

-- ---------------------------------------------------------------------------
-- Q2: Month-over-month trend in total encounter volume, total billed cost,
-- total payer-covered amount, and patient responsibility (total billed minus
-- what the payer covered -- i.e. what's left as the patient's).
--
-- Scoped to the last 15 years (see the WHERE below) instead of the full
-- 1912-2026 span the raw data covers -- Synthea backdates a handful of very
-- old synthetic patients' histories for decades, and those early years are
-- 1-2 encounters each: statistical noise that would swamp any real
-- month-over-month read if left in. 15 years is a starting point, not a
-- hard rule -- widen or narrow it once you've actually looked at how far
-- back real volume density holds up.
--
-- NOTE on patient_responsibility: this is what a patient was BILLED as
-- owing, not what was actually collected from them -- Synthea has no
-- payments/collections ledger, so there's no way to tell a fully-paid
-- balance from a still-outstanding one from this data alone. Report it as
-- "billed vs. payer-covered," not as real recovered revenue.
-- ---------------------------------------------------------------------------
SELECT
    dd.year_num,
    dd.month_num,
    dd.month_name,
    COUNT(*)                                          AS encounter_volume,
    SUM(fe.total_claim_cost)                          AS total_claim_cost,
    SUM(fe.payer_coverage)                             AS total_payer_coverage,
    SUM(fe.total_claim_cost) - SUM(fe.payer_coverage) AS patient_responsibility
FROM fact_encounters fe
JOIN dim_date dd ON dd.date_key = fe.start_date_key
WHERE dd.full_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 15 YEAR)
GROUP BY dd.year_num, dd.month_num, dd.month_name
ORDER BY dd.year_num, dd.month_num;

-- ---------------------------------------------------------------------------
-- Q3: Which patients have the highest total healthcare spend, and what's
-- driving it (encounters vs. medications vs. procedures)?
-- Each cost source is summed separately first (so a patient with, say, no
-- procedures still shows up correctly with $0 there instead of being
-- dropped), then combined into a single total for ranking.
--
-- KNOWN LIMITATION (SCD Type 2, not yet an issue): the three cost CTEs
-- below group by patient_key -- the dim_patient SURROGATE key -- and the
-- final join keeps only is_current = 1 rows. On this first load every
-- patient has exactly one dim_patient row, so patient_key and "this
-- person" are the same thing and totals below are correct. But once a
-- future reload closes out a changed patient row (Type 2 SCD) and opens a
-- new current one, any fact rows still pointing at the OLD surrogate key
-- will stop matching the current row here and silently drop out of
-- total_spend -- no error, just a quietly understated total for anyone
-- who's had a tracked attribute change. Fix when that day comes: roll the
-- cost CTEs up by patient_id (join fact -> ALL dim_patient versions, not
-- just is_current = 1) before joining back to the current row for display
-- attributes. Deliberately left as-is for now -- planned to surface and
-- fix this for real as part of the Q9 Type 2 SCD / as-of work.
-- ---------------------------------------------------------------------------
WITH encounter_spend AS (
    SELECT patient_key, SUM(total_claim_cost) AS encounter_cost
    FROM fact_encounters
    GROUP BY patient_key
),
medication_spend AS (
    SELECT patient_key, SUM(total_cost) AS medication_cost
    FROM fact_medications
    GROUP BY patient_key
),
procedure_spend AS (
    SELECT patient_key, SUM(base_cost) AS procedure_cost
    FROM fact_procedures
    GROUP BY patient_key
)
SELECT
    dp.patient_id,
    dp.first_name,
    dp.last_name,
    COALESCE(es.encounter_cost, 0)  AS encounter_cost,
    COALESCE(ms.medication_cost, 0) AS medication_cost,
    COALESCE(ps.procedure_cost, 0)  AS procedure_cost,
    COALESCE(es.encounter_cost, 0) + COALESCE(ms.medication_cost, 0) + COALESCE(ps.procedure_cost, 0)
        AS total_spend
FROM dim_patient dp
LEFT JOIN encounter_spend es  ON es.patient_key = dp.patient_key
LEFT JOIN medication_spend ms ON ms.patient_key = dp.patient_key
LEFT JOIN procedure_spend ps  ON ps.patient_key = dp.patient_key
WHERE dp.is_current = 1
ORDER BY total_spend DESC
LIMIT 20;

-- ---------------------------------------------------------------------------
-- Q4a: Average length of stay by encounter class, with spread (min/max/
-- standard deviation) included so you can see how much variation there is
-- within each class before calling anything an "outlier."
-- ---------------------------------------------------------------------------
SELECT
    fe.encounter_class,
    COUNT(*)                        AS encounter_count,
    AVG(fe.length_of_stay_hours)    AS avg_los_hours,
    MIN(fe.length_of_stay_hours)    AS min_los_hours,
    MAX(fe.length_of_stay_hours)    AS max_los_hours,
    STDDEV(fe.length_of_stay_hours) AS stddev_los_hours
FROM fact_encounters fe
WHERE fe.length_of_stay_hours IS NOT NULL
GROUP BY fe.encounter_class
ORDER BY avg_los_hours DESC;

-- ---------------------------------------------------------------------------
-- Q4b: Flag individual encounters whose length of stay is an outlier
-- relative to their own encounter class -- defined here as more than 3
-- standard deviations above that class's average. (3 standard deviations is
-- a common rule-of-thumb threshold; adjust it if it flags too many/few rows
-- once you see the real results.)
-- ---------------------------------------------------------------------------
WITH class_stats AS (
    SELECT
        encounter_class,
        AVG(length_of_stay_hours)    AS avg_los,
        STDDEV(length_of_stay_hours) AS stddev_los
    FROM fact_encounters
    WHERE length_of_stay_hours IS NOT NULL
    GROUP BY encounter_class
)
SELECT
    fe.encounter_id,
    fe.encounter_class,
    fe.length_of_stay_hours,
    cs.avg_los,
    cs.stddev_los
FROM fact_encounters fe
JOIN class_stats cs ON cs.encounter_class = fe.encounter_class
WHERE fe.length_of_stay_hours > cs.avg_los + (3 * cs.stddev_los)
ORDER BY fe.length_of_stay_hours DESC;

-- ---------------------------------------------------------------------------
-- Q5a: Organizations by patient volume vs. average cost per encounter.
--
-- Same KNOWN LIMITATION as Q3 above: COUNT(DISTINCT fe.patient_key) counts
-- distinct surrogate keys, not distinct people. Once dim_patient starts
-- carrying multiple versions per person, a patient who visited before and
-- after a tracked attribute change would count as 2 in patient_volume
-- instead of 1. Left as-is for the same reason -- revisit with Q9.
-- ---------------------------------------------------------------------------
SELECT
    do_.name                       AS organization_name,
    COUNT(DISTINCT fe.patient_key) AS patient_volume,
    COUNT(*)                       AS encounter_count,
    AVG(fe.total_claim_cost)       AS avg_cost_per_encounter
FROM fact_encounters fe
JOIN dim_organization do_ ON do_.organization_key = fe.organization_key
GROUP BY do_.name
ORDER BY patient_volume DESC;

-- ---------------------------------------------------------------------------
-- Q5b: Same idea, but by individual provider instead of organization.
-- Same surrogate-key/patient_volume caveat as Q5a -- see that note.
--
-- CONFIRMED DATA CHARACTERISTIC (not a bug): this query's results come back
-- numerically identical to Q5a's, row for row. Verified this isn't a load
-- error -- checked 02_load_staging.sql (provider column maps to the right
-- CSV field) and 05_load_facts.sql (dim_provider join is keyed correctly)
-- and both are fine. The real cause:
--   SELECT organization_key, COUNT(DISTINCT provider_key) num_providers
--   FROM dim_provider GROUP BY organization_key;         -- e.g. 345, 128, 116...
--   SELECT organization_key, COUNT(DISTINCT provider_key) distinct_providers_used
--   FROM fact_encounters GROUP BY organization_key;      -- all 1s
-- Each organization rosters hundreds of providers in providers.csv, but in
-- this Synthea export essentially all of that org's actual encounter volume
-- (especially the big "wellness" bucket from Q4a) is attributed to just one
-- of them. So provider-level and organization-level cuts collapse to the
-- same numbers in this dataset -- a real characteristic of the source data,
-- not something to "fix" in the ETL.
-- ---------------------------------------------------------------------------
SELECT
    dpr.name                       AS provider_name,
    COUNT(DISTINCT fe.patient_key) AS patient_volume,
    COUNT(*)                       AS encounter_count,
    AVG(fe.total_claim_cost)       AS avg_cost_per_encounter
FROM fact_encounters fe
JOIN dim_provider dpr ON dpr.provider_key = fe.provider_key
GROUP BY dpr.name
ORDER BY patient_volume DESC;

-- ---------------------------------------------------------------------------
-- Q6a: For each patient, days since their most recent encounter (relative
-- to today), ranked with the longest gaps first -- the patients most
-- overdue for a visit at the top. This is the recency/outreach half of Q6,
-- kept deliberately separate from Q6b (readmission gap between consecutive
-- inpatient stays, not yet written here) -- the two answer different
-- business questions for different stakeholders, see README.
--
-- Business question: who's falling out of care right now and needs
-- outreach. Stakeholder: care management / population health.
--
-- Uses DATEDIFF(), not the `-` operator -- MySQL's `-` between two dates
-- doesn't compute elapsed days, it numifies both sides to their YYYYMMDD
-- form and subtracts THAT, which produces a meaningless inflated number
-- once the two dates cross a month/year boundary. DATEDIFF() is the actual
-- "how many days apart are these" function.
--
-- KNOWN LIMITATION (same surrogate-key/SCD root cause as Q3 and Q5a/Q5b,
-- not yet an issue): ROW_NUMBER() here partitions by
-- fact_encounters.patient_key -- the surrogate key stamped onto each
-- encounter at LOAD time, not the person's durable patient_id. On this
-- first load every patient has exactly one dim_patient row/key, so this is
-- correct as written. But once a future Type 2 reload closes out a changed
-- patient row and opens a new one, any NEW encounters loaded afterward will
-- carry the NEW surrogate key while this patient's OLDER encounters keep
-- their OLD one -- so this query would see what's really one person as two
-- separate patient_key groups, each getting its own "most recent
-- encounter" row. Net effect here isn't a dropped total (Q3) or an
-- inflated headcount (Q5a/b), it's a DUPLICATED person on the outreach
-- list -- showing up twice under two different keys, with neither row
-- reflecting their true most-recent visit across their full history. Same
-- fix as the others: roll up by patient_id across all of a person's
-- dim_patient versions before ranking, join back to the current row only
-- for display. Deliberately left as-is for now -- revisit at Q9.
-- ---------------------------------------------------------------------------
WITH enc_ranking AS (
    SELECT
        dim_patient.patient_key,
        dim_patient.last_name,
        dim_patient.first_name,
        dim_date.full_date AS encounter_date,
        ROW_NUMBER() OVER (
            PARTITION BY fact_encounters.patient_key
            ORDER BY dim_date.full_date DESC
        ) AS order_sequence
    FROM fact_encounters
    JOIN dim_date    ON fact_encounters.start_date_key = dim_date.date_key
    JOIN dim_patient ON fact_encounters.patient_key = dim_patient.patient_key
)
SELECT
    last_name,
    first_name,
    encounter_date                           AS most_recent_encounter,
    DATEDIFF(CURRENT_DATE(), encounter_date) AS days_since_last_seen
FROM enc_ranking
WHERE order_sequence = 1
ORDER BY days_since_last_seen DESC;

-- ---------------------------------------------------------------------------
-- Q6b: Inpatient readmission gap -- CMS-style, simplified all-cause proxy for
-- the Hospital Readmissions Reduction Program measure.
--
-- Design decisions:
--   - Filtered to encounter_class = 'inpatient' only (under 3% of all
--     encounters) -- an unfiltered version comparing gaps between ANY two
--     encounters would silently answer a different, much noisier question.
--   - All-cause, not diagnosis-matched: the readmission doesn't need to
--     share a condition with the index stay. Deliberate simplification of
--     CMS's real measure, which is condition-specific with
--     planned-readmission exclusions -- neither is modeled here.
--   - LAG() is partitioned by dim_patient.patient_id -- the durable natural
--     key -- rather than fact_encounters.patient_key, the load-time
--     surrogate. That sidesteps the SCD Type 2 surrogate-key limitation
--     documented on Q3/Q5a/Q5b/Q6a above (a future reload that opens a new
--     dim_patient row for a changed patient would fragment this partition
--     under patient_key; patient_id stays correct across that).
--   - 30-day window is inclusive: `<= 30`, not `< 30`, matching CMS's
--     "within 30 days of discharge" convention -- a readmission landing
--     exactly on day 30 counts, day 31 does not.
--   - A patient's first/only inpatient stay has no prior discharge to
--     compare against -- LAG() returns NULL for it, and DATEDIFF() against
--     a NULL previous discharge is itself NULL, which is not <= 30, so the
--     WHERE clause drops those rows without an explicit IS NOT NULL check.
--
-- KNOWN DATA ISSUE (left in on purpose, not filtered out): a handful of
-- rows come back with days_since_previous_encounter_end at 0 or negative.
-- Checked -- this happens when a patient has two inpatient encounter rows
-- that overlap in time (the "previous" stay's end date falls on or after
-- the "current" stay's start date), not from a bad/missing stop_ts. It
-- isn't really a hospital-transfer scenario in the CMS sense (same
-- encounter_class, no separate receiving facility) -- it looks more like
-- one hospitalization logged as multiple overlapping 'inpatient' encounter
-- rows in the source data. CMS's own measure spec has related but narrower
-- guidance that doesn't quite cover this: a same-hospital, same-day,
-- same-condition readmission is treated as one continuous admission, and
-- multi-hospital transfer chains are attributed to the final discharging
-- hospital -- neither rule maps cleanly onto overlapping same-source
-- encounter records, so there's no direct CMS precedent to lean on here.
-- Flagged rather than silently filtered, since a gap of 0 or a small
-- negative number is a real, visible signal that the "sequential inpatient
-- stay" assumption breaks down for some records, not noise to hide.
--
-- ALSO WORTH NOTING (not yet addressed): dim_date is day-grain only --
-- fact_encounters exposes no admission/discharge timestamp, just
-- start_date_key/stop_date_key. If a patient has two inpatient encounters
-- starting on the same calendar day, ORDER BY encstartdate.full_date has no
-- secondary sort key to break the tie, so which row LAG() treats as
-- "previous" isn't guaranteed stable/reproducible run to run. A fix would
-- need either an encounter_id tiebreaker in the ORDER BY or exposing a
-- finer-grained start timestamp on fact_encounters.
-- ---------------------------------------------------------------------------
WITH enc_with_previous_enc_end_dates AS (
    SELECT
        dim_patient.patient_key,
        dim_patient.last_name,
        dim_patient.first_name,
        encstartdate.full_date AS encounter_start_date,
        encenddate.full_date   AS encounter_end_date,
        LAG(encenddate.full_date) OVER (
            PARTITION BY dim_patient.patient_id
            ORDER BY encstartdate.full_date
        ) AS previous_encounter_end_date
    FROM fact_encounters
    JOIN dim_date encstartdate ON fact_encounters.start_date_key = encstartdate.date_key
    JOIN dim_date encenddate   ON fact_encounters.stop_date_key  = encenddate.date_key
    JOIN dim_patient            ON fact_encounters.patient_key    = dim_patient.patient_key
    WHERE fact_encounters.encounter_class = 'inpatient'
)
SELECT
    last_name,
    first_name,
    encounter_start_date,
    previous_encounter_end_date,
    DATEDIFF(encounter_start_date, previous_encounter_end_date) AS days_since_previous_encounter_end
FROM enc_with_previous_enc_end_dates
WHERE DATEDIFF(encounter_start_date, previous_encounter_end_date) <= 30;

-- ---------------------------------------------------------------------------
-- Q7: Condition trend pivot -- top 10 real diagnoses (the same "(disorder)"
-- list from Q1a), one column per calendar year, to see which are trending
-- up or down.
--
-- Business question: which diagnoses are becoming more or less common over
-- time in this population -- used to spot emerging health trends early
-- enough to shift staffing, service lines, or screening programs toward
-- them.
-- Stakeholder: population health / clinical program planning.
--
-- Scoped to whole calendar years 2012-2026 -- same last-15-years reasoning
-- as Q2 (Synthea's backdated early years are 1-2 encounters each and would
-- swamp any real trend), but using clean year boundaries here since the
-- pivot needs to align on calendar years, not a rolling 15-year lookback
-- from today's exact date.
--
-- Built with manual CASE-based pivoting (one column per year), matching the
-- curriculum's pivoting concept -- MySQL has no native PIVOT operator. Known
-- tradeoff of this approach vs. dynamic SQL: the year columns are hardcoded
-- and need updating by hand as more years of data accumulate.
-- ---------------------------------------------------------------------------
WITH top_disorders AS (
    SELECT fc.code, fc.description, COUNT(DISTINCT fc.patient_key) AS patient_count
    FROM fact_conditions fc
    WHERE fc.description LIKE '%(disorder)%'
    GROUP BY fc.code, fc.description
    ORDER BY patient_count DESC
    LIMIT 10
)
SELECT
    td.description,
    SUM(CASE WHEN dd.year_num = 2012 THEN 1 ELSE 0 END) AS `2012`,
    SUM(CASE WHEN dd.year_num = 2013 THEN 1 ELSE 0 END) AS `2013`,
    SUM(CASE WHEN dd.year_num = 2014 THEN 1 ELSE 0 END) AS `2014`,
    SUM(CASE WHEN dd.year_num = 2015 THEN 1 ELSE 0 END) AS `2015`,
    SUM(CASE WHEN dd.year_num = 2016 THEN 1 ELSE 0 END) AS `2016`,
    SUM(CASE WHEN dd.year_num = 2017 THEN 1 ELSE 0 END) AS `2017`,
    SUM(CASE WHEN dd.year_num = 2018 THEN 1 ELSE 0 END) AS `2018`,
    SUM(CASE WHEN dd.year_num = 2019 THEN 1 ELSE 0 END) AS `2019`,
    SUM(CASE WHEN dd.year_num = 2020 THEN 1 ELSE 0 END) AS `2020`,
    SUM(CASE WHEN dd.year_num = 2021 THEN 1 ELSE 0 END) AS `2021`,
    SUM(CASE WHEN dd.year_num = 2022 THEN 1 ELSE 0 END) AS `2022`,
    SUM(CASE WHEN dd.year_num = 2023 THEN 1 ELSE 0 END) AS `2023`,
    SUM(CASE WHEN dd.year_num = 2024 THEN 1 ELSE 0 END) AS `2024`,
    SUM(CASE WHEN dd.year_num = 2025 THEN 1 ELSE 0 END) AS `2025`,
    SUM(CASE WHEN dd.year_num = 2026 THEN 1 ELSE 0 END) AS `2026`
FROM fact_conditions fc
JOIN top_disorders td ON td.code = fc.code
JOIN dim_date dd      ON dd.date_key = fc.onset_date_key
WHERE dd.year_num BETWEEN 2012 AND 2026
GROUP BY td.description
ORDER BY td.description;

-- ---------------------------------------------------------------------------
-- Q8: Anti-join -- patients 45+ who have never had a diabetes diagnosis or
-- diabetes-related condition documented, despite being in the age range
-- where screening guidance (USPSTF/ADA) generally applies.
--
-- Business question: a gap-in-care/outreach list -- the same shape as a
-- HEDIS-style screening-compliance report.
-- Stakeholder: preventive care / population health, quality improvement.
--
-- Matches broadly on "diabetes" in the condition description (catches
-- complications and prediabetes too, not just a strict type-2 diagnosis
-- code) so a patient who's been evaluated for anything diabetes-adjacent
-- isn't miscounted as a screening gap. Excludes deceased patients -- an
-- outreach list for screening only makes sense for patients still eligible
-- to be screened. Classic LEFT JOIN / IS NULL anti-join pattern.
-- ---------------------------------------------------------------------------
SELECT
    dp.patient_id,
    dp.first_name,
    dp.last_name,
    TIMESTAMPDIFF(YEAR, dp.birth_date, CURRENT_DATE()) AS current_age
FROM dim_patient dp
LEFT JOIN fact_conditions fc
    ON fc.patient_key = dp.patient_key
    AND fc.description LIKE '%diabetes%'
WHERE dp.is_current = 1
  AND dp.death_date IS NULL
  AND TIMESTAMPDIFF(YEAR, dp.birth_date, CURRENT_DATE()) >= 45
  AND fc.condition_key IS NULL
ORDER BY current_age DESC;

-- ---------------------------------------------------------------------------
-- Q9: As-of query against dim_patient -- what did a patient's on-file
-- demographic info look like as of a specific past date, not what it shows
-- today.
--
-- Business question: reconstruct what our records said about a patient as
-- of a specific date -- e.g. verifying what was on file at the time of a
-- claim, encounter, or care decision, not what's true about them today.
-- Stakeholder: data governance / compliance; care coordination doing a
-- retrospective case review.
--
-- REQUIRES sql/07_simulate_scd_change.sql to have been run first. Without
-- it, dim_patient has exactly one version per patient and this returns the
-- same row for any date -- proving the query logic works but not
-- demonstrating a real before/after.
--
-- Logic: instead of filtering on is_current = 1 (which only ever answers
-- "what's true right now"), find whichever version's
-- [effective_start_date, effective_end_date) window contains the date in
-- question -- treating a NULL effective_end_date as "still open."
--
-- Run both SELECTs below as-is: same patient (one of the 5 simulated in 07,
-- picked automatically), same query shape, but one @as_of_date before the
-- simulated change and one after -- marital_status should visibly flip
-- between the two results.
-- ---------------------------------------------------------------------------
SET @target_patient_id = (
    SELECT patient_id FROM dim_patient GROUP BY patient_id HAVING COUNT(*) > 1 LIMIT 1
);

-- As of a date BEFORE the simulated change (2023-06-01) -- should return
-- the original marital_status.
SET @as_of_date = '2022-01-01';
SELECT
    patient_id, first_name, last_name, marital_status,
    effective_start_date, effective_end_date, is_current
FROM dim_patient
WHERE patient_id = @target_patient_id
  AND effective_start_date <= @as_of_date
  AND (effective_end_date IS NULL OR effective_end_date > @as_of_date);

-- As of a date AFTER the simulated change -- should return the flipped
-- marital_status instead.
SET @as_of_date = '2024-01-01';
SELECT
    patient_id, first_name, last_name, marital_status,
    effective_start_date, effective_end_date, is_current
FROM dim_patient
WHERE patient_id = @target_patient_id
  AND effective_start_date <= @as_of_date
  AND (effective_end_date IS NULL OR effective_end_date > @as_of_date);
