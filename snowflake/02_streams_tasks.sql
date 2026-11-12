-- =====================================================================
-- 02_streams_tasks.sql — change data capture with Streams + Tasks
--
-- A STREAM records every row-level change (insert, update, delete) made to
-- its table since the stream was last consumed. A TASK consumes it on a
-- schedule and appends the changes to an immutable change log in RAW.
-- The legacy tables keep working untouched: this is the "run old and new
-- side by side" pattern used in real migrations.
-- =====================================================================

USE ROLE CDC_ENGINEER;
USE WAREHOUSE WH_CDC;
USE DATABASE INSURANCE_CDC;

-- ---------------------------------------------------------------------
-- Change log tables (append-only, never updated or deleted)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RAW.POLICY_CHANGES (
    change_id         NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    cdc_operation     VARCHAR(1)    NOT NULL,   -- I = insert, U = update, D = delete
    cdc_captured_at   TIMESTAMP_NTZ NOT NULL,
    policy_id         NUMBER(12,0),
    product_line      VARCHAR(20),
    region            VARCHAR(10),
    area              VARCHAR(2),
    vehicle_brand     VARCHAR(10),
    vehicle_power     NUMBER(4,0),
    vehicle_age       NUMBER(4,0),
    vehicle_fuel      VARCHAR(10),
    driver_age        NUMBER(4,0),
    bonus_malus       NUMBER(5,0),
    density           NUMBER(10,0),
    annual_premium    NUMBER(12,2),
    status            VARCHAR(12),
    start_date        DATE,
    end_date          DATE,
    source_updated_at TIMESTAMP_NTZ
);

CREATE TABLE IF NOT EXISTS RAW.ENDORSEMENT_CHANGES (
    change_id         NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    cdc_operation     VARCHAR(1)    NOT NULL,
    cdc_captured_at   TIMESTAMP_NTZ NOT NULL,
    endorsement_id    NUMBER(14,0),
    policy_id         NUMBER(12,0),
    endorsement_type  VARCHAR(30),
    premium_delta     NUMBER(12,2),
    new_region        VARCHAR(10),
    new_vehicle_age   NUMBER(4,0),
    effective_date    DATE,
    batch_id          VARCHAR(36),
    created_at        TIMESTAMP_NTZ
);

-- ---------------------------------------------------------------------
-- Streams on the legacy tables.
-- SHOW_INITIAL_ROWS = TRUE makes the first read return the rows that already
-- exist (the "full load"); after that the stream returns only changes.
-- ---------------------------------------------------------------------
CREATE STREAM IF NOT EXISTS RAW.POLICIES_STREAM
  ON TABLE LEGACY.POLICIES
  SHOW_INITIAL_ROWS = TRUE;

CREATE STREAM IF NOT EXISTS RAW.ENDORSEMENTS_STREAM
  ON TABLE LEGACY.ENDORSEMENTS
  SHOW_INITIAL_ROWS = TRUE;

-- ---------------------------------------------------------------------
-- Tasks: every minute, but only when the stream has data
-- (SYSTEM$STREAM_HAS_DATA skips the run and costs no warehouse time).
--
-- In a stream an UPDATE appears as two rows: a DELETE and an INSERT, both
-- with METADATA$ISUPDATE = TRUE. We keep the INSERT side (the new values)
-- and label it 'U'. A real DELETE has ISUPDATE = FALSE and is kept as 'D'.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TASK RAW.CAPTURE_POLICY_CHANGES
  WAREHOUSE = WH_CDC
  SCHEDULE = '1 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('RAW.POLICIES_STREAM')
AS
INSERT INTO RAW.POLICY_CHANGES (
    cdc_operation, cdc_captured_at, policy_id, product_line, region, area,
    vehicle_brand, vehicle_power, vehicle_age, vehicle_fuel, driver_age,
    bonus_malus, density, annual_premium, status, start_date, end_date,
    source_updated_at
)
SELECT
    CASE
        WHEN METADATA$ACTION = 'INSERT' AND METADATA$ISUPDATE THEN 'U'
        WHEN METADATA$ACTION = 'INSERT' THEN 'I'
        ELSE 'D'
    END,
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
    policy_id, product_line, region, area, vehicle_brand, vehicle_power,
    vehicle_age, vehicle_fuel, driver_age, bonus_malus, density,
    annual_premium, status, start_date, end_date, updated_at
FROM RAW.POLICIES_STREAM
WHERE NOT (METADATA$ACTION = 'DELETE' AND METADATA$ISUPDATE);

CREATE OR REPLACE TASK RAW.CAPTURE_ENDORSEMENT_CHANGES
  WAREHOUSE = WH_CDC
  SCHEDULE = '1 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('RAW.ENDORSEMENTS_STREAM')
AS
INSERT INTO RAW.ENDORSEMENT_CHANGES (
    cdc_operation, cdc_captured_at, endorsement_id, policy_id, endorsement_type,
    premium_delta, new_region, new_vehicle_age, effective_date, batch_id, created_at
)
SELECT
    CASE
        WHEN METADATA$ACTION = 'INSERT' AND METADATA$ISUPDATE THEN 'U'
        WHEN METADATA$ACTION = 'INSERT' THEN 'I'
        ELSE 'D'
    END,
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
    endorsement_id, policy_id, endorsement_type, premium_delta, new_region,
    new_vehicle_age, effective_date, batch_id, created_at
FROM RAW.ENDORSEMENTS_STREAM
WHERE NOT (METADATA$ACTION = 'DELETE' AND METADATA$ISUPDATE);

-- Tasks are created suspended. Start them:
ALTER TASK RAW.CAPTURE_POLICY_CHANGES RESUME;
ALTER TASK RAW.CAPTURE_ENDORSEMENT_CHANGES RESUME;

-- Useful checks:
--   SHOW STREAMS IN SCHEMA RAW;
--   SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY()) ORDER BY scheduled_time DESC LIMIT 20;
--   SELECT cdc_operation, COUNT(*) FROM RAW.POLICY_CHANGES GROUP BY 1;
