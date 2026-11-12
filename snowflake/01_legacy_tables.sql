-- =====================================================================
-- 01_legacy_tables.sql — the simulated legacy operational system
-- The simulator writes inserts, updates and deletes here, exactly like
-- the production application would in a real legacy database.
-- =====================================================================

USE ROLE CDC_ENGINEER;
USE WAREHOUSE WH_CDC;
USE SCHEMA INSURANCE_CDC.LEGACY;

-- Public seed data: French Motor Third-Party Liability portfolio (freMTPL2freq),
-- loaded by `python -m simulator.seed`. Rows not yet "sold" act as a pool of
-- new policies the simulator can issue later.
CREATE TABLE IF NOT EXISTS POLICY_SEED_POOL (
    policy_id      NUMBER(12,0) NOT NULL,
    exposure_years NUMBER(6,4),
    area           VARCHAR(2),
    vehicle_power  NUMBER(4,0),
    vehicle_age    NUMBER(4,0),
    driver_age     NUMBER(4,0),
    bonus_malus    NUMBER(5,0),
    vehicle_brand  VARCHAR(10),
    vehicle_fuel   VARCHAR(10),
    density        NUMBER(10,0),
    region         VARCHAR(10),
    claim_count    NUMBER(4,0)
);

-- Policies ("apólices") as the legacy system stores them: one row per policy,
-- overwritten in place on every change. No history is kept here.
CREATE TABLE IF NOT EXISTS POLICIES (
    policy_id      NUMBER(12,0)  NOT NULL PRIMARY KEY,
    product_line   VARCHAR(20)   NOT NULL,
    region         VARCHAR(10),
    area           VARCHAR(2),
    vehicle_brand  VARCHAR(10),
    vehicle_power  NUMBER(4,0),
    vehicle_age    NUMBER(4,0),
    vehicle_fuel   VARCHAR(10),
    driver_age     NUMBER(4,0),
    bonus_malus    NUMBER(5,0),
    density        NUMBER(10,0),
    annual_premium NUMBER(12,2)  NOT NULL,
    status         VARCHAR(12)   NOT NULL,   -- ACTIVE | CANCELLED
    start_date     DATE          NOT NULL,
    end_date       DATE,
    updated_at     TIMESTAMP_NTZ NOT NULL
);

-- Endorsements ("endossos"): every change to a policy after issuance.
CREATE TABLE IF NOT EXISTS ENDORSEMENTS (
    endorsement_id   NUMBER(14,0)  NOT NULL PRIMARY KEY,
    policy_id        NUMBER(12,0)  NOT NULL,
    endorsement_type VARCHAR(30)   NOT NULL, -- PREMIUM_ADJUSTMENT | VEHICLE_CHANGE | ADDRESS_CHANGE | CANCELLATION
    premium_delta    NUMBER(12,2)  NOT NULL,
    new_region       VARCHAR(10),
    new_vehicle_age  NUMBER(4,0),
    effective_date   DATE          NOT NULL,
    batch_id         VARCHAR(36)   NOT NULL,
    created_at       TIMESTAMP_NTZ NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS ENDORSEMENT_SEQ START = 1 INCREMENT = 1;
