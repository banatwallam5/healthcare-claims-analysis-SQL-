# Healthcare Data Analytics (Synthea)

A SQL analytics project built on [Synthea](https://github.com/synthetichealth/synthea) synthetic patient
data, modeled as a star schema and queried in MySQL. Built to demonstrate practical
data-analyst SQL: schema design, ETL/data cleaning, window functions, and answering
real operational and clinical questions from patient-level data.

**Status: in progress.** This README will be filled in with actual findings, screenshots,
and numbers as the project is built. Right now it's the design doc.

## Why this project

I have a background in EHR/healthcare systems, and wanted a portfolio piece that plays
to that rather than a generic retail/e-commerce dataset every other candidate uses.
Synthea generates fully synthetic patient populations (no real PHI, no compliance risk)
that are still structurally realistic — encounters, diagnoses, medications, procedures,
and vitals/labs, all tied together the way a real EHR export would be.

## Dataset

[Synthea](https://github.com/synthetichealth/synthea) — MITRE's open-source synthetic
patient generator. Data is 100% synthetic; no real patient information is used anywhere
in this project.

**Getting the data** (pick one):
- **Run the generator yourself** (recommended — lets you size and pick a state):
  1. Install Java, then clone `https://github.com/synthetichealth/synthea`.
  2. In `src/main/resources/synthea.properties`, set `exporter.csv.export = true`.
  3. Run `./run_synthea -p 1000 Massachusetts` (swap in the patient count / state you want).
  4. CSV files land in `./output/csv/`.
- **Pre-generated downloads**: MITRE also publishes ready-made sample populations at
  [synthea.mitre.org/downloads](https://synthea.mitre.org/downloads) if you'd rather skip
  running the generator.

This project uses 8 of Synthea's ~18 CSV exports for v1: `patients`, `encounters`,
`conditions`, `medications`, `procedures`, `observations`, `organizations`, `providers`.
(`immunizations`, `allergies`, `careplans`, `devices`, `imaging_studies`, `supplies`,
`payers`, `payer_transitions` are candidates for a v2 extension.)

## Architecture

Two layers, both in MySQL (built/run locally in MySQL Workbench):

```
Synthea CSVs  --(LOAD DATA)-->  Staging tables (stg_*)  --(SQL transform)-->  Star schema
```

**Staging layer** — one table per CSV, columns as close to the raw export as possible.
Nothing is cleaned or typed strictly here; that isolates "did the load work" from "is the
transform correct."

**Star schema:**

| Table | Type | Grain |
|---|---|---|
| `dim_date` | dimension | one row per calendar day |
| `dim_patient` | dimension, **Type 2 SCD** | one row per patient version |
| `dim_organization` | dimension, Type 1 | one row per facility |
| `dim_provider` | dimension, Type 1 | one row per provider |
| `fact_encounters` | fact | one row per encounter |
| `fact_conditions` | fact (factless) | one row per diagnosed condition |
| `fact_medications` | fact | one row per medication order |
| `fact_procedures` | fact | one row per procedure performed |
| `fact_observations` | fact | one row per recorded observation (vital/lab/survey) |

`dim_patient` is built as a real Type 2 SCD (`effective_start_date`, `effective_end_date`,
`is_current`) even though the first Synthea export is a single snapshot — the structure is
there so that a second export, re-loaded later, would actually accumulate patient history
instead of silently overwriting it.

See [`sql/`](./sql) for the full DDL and load scripts, run in order 01 → 05.

## Planned analysis questions

Drawn from what the study curriculum has covered so far (joins/anti-joins, aggregation,
CTEs, window functions, date/time analysis, CASE/pivoting) — answers and query code will
be added here as they're built:

1. What are the top 10 most common diagnosed conditions, and how does prevalence differ
   by age band and gender?
2. What's the month-over-month trend in total encounter volume and total claim cost?
3. Which patients have the highest total healthcare spend, and what's driving it
   (encounters vs. medications vs. procedures)?
4. What's the average length of stay by encounter class (inpatient/outpatient/emergency),
   and are there outliers worth flagging?
5. Which providers/organizations have the highest patient volume, and how does that
   correlate with average cost per encounter?
6. Using window functions: for each patient, what's their most recent encounter and how
   many days since their previous one (readmission-style analysis)?
7. Pivot: condition counts by year, one column per year, to see which diagnoses are
   trending up or down over time.
8. Anti-join: which patients have never had a documented encounter for a
   [specific chronic condition] despite being in an at-risk demographic?
9. As-of query against `dim_patient`: what did a patient's on-file demographic info look
   like at a specific point in time (exercises the Type 2 SCD design even on v1 data).

## Setup

1. Get Synthea CSV output (see "Getting the data" above).
2. In MySQL Workbench, run `sql/01_staging_schema.sql`.
3. Edit the file paths in `sql/02_load_staging.sql` to point at your CSVs, then run it.
4. Run `sql/03_star_schema.sql`.
5. Run `sql/04_load_dimensions.sql`, then `sql/05_load_facts.sql`.
6. Each script ends with a row-count sanity check — confirm counts look reasonable
   before moving to analysis queries.

## Tech

MySQL 8 (MySQL Workbench), SQL only for v1. Excel/BI-tool visualizations may be added
as the study plan reaches that phase.
