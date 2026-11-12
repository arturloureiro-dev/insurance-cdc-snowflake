-- =====================================================================
-- 00_setup.sql — account objects for the insurance CDC project
-- Run once as ACCOUNTADMIN (or a role with CREATE DATABASE / ROLE / USER).
-- =====================================================================

USE ROLE ACCOUNTADMIN;

-- Compute: one X-Small warehouse that suspends after 60 s of idle time.
CREATE WAREHOUSE IF NOT EXISTS WH_CDC
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Insurance CDC portfolio project';

-- Cost guardrail: stop the warehouse if it burns more than 10 credits a month.
CREATE RESOURCE MONITOR IF NOT EXISTS RM_CDC
  WITH CREDIT_QUOTA = 10
  FREQUENCY = MONTHLY
  START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND;
ALTER WAREHOUSE WH_CDC SET RESOURCE_MONITOR = RM_CDC;

-- Database and the three layers:
--   LEGACY    = simulates the legacy operational system (the "source")
--   RAW       = append-only change log captured by Streams + Tasks
--   ANALYTICS = dbt models (staging, intermediate, marts)
CREATE DATABASE IF NOT EXISTS INSURANCE_CDC;
CREATE SCHEMA IF NOT EXISTS INSURANCE_CDC.LEGACY;
CREATE SCHEMA IF NOT EXISTS INSURANCE_CDC.RAW;
CREATE SCHEMA IF NOT EXISTS INSURANCE_CDC.ANALYTICS;

-- One functional role for the whole project.
CREATE ROLE IF NOT EXISTS CDC_ENGINEER;
GRANT USAGE, OPERATE ON WAREHOUSE WH_CDC TO ROLE CDC_ENGINEER;
GRANT ALL ON DATABASE INSURANCE_CDC TO ROLE CDC_ENGINEER;
GRANT ALL ON ALL SCHEMAS IN DATABASE INSURANCE_CDC TO ROLE CDC_ENGINEER;
GRANT EXECUTE TASK ON ACCOUNT TO ROLE CDC_ENGINEER;
GRANT ROLE CDC_ENGINEER TO ROLE SYSADMIN;

-- Service user with key-pair authentication (no password).
-- Generate the key pair first (see README) and paste the PUBLIC key below.
CREATE USER IF NOT EXISTS SVC_CDC
  TYPE = SERVICE
  DEFAULT_ROLE = CDC_ENGINEER
  DEFAULT_WAREHOUSE = WH_CDC
  RSA_PUBLIC_KEY = '<PASTE_PUBLIC_KEY_WITHOUT_HEADER_AND_FOOTER>';
GRANT ROLE CDC_ENGINEER TO USER SVC_CDC;
