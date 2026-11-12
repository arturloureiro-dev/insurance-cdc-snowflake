"""SQL used by the seeder and the simulator, kept in one place."""

# freMTPL2 has no premium column, so the legacy system "prices" each policy with
# a simple, documented rating formula. It is synthetic on purpose and only
# exists to give endorsements a realistic number to change.
PREMIUM_FORMULA = """
ROUND(
    350
    * (bonus_malus / 100)
    * (1 + (vehicle_power - 4) * 0.05)
    * IFF(driver_age < 25, 1.6, 1)
    * (1 + LN(GREATEST(density, 1)) / 20),
2)
"""

# Issue new policies from the public seed pool (rows not yet in POLICIES).
ISSUE_POLICIES = f"""
INSERT INTO POLICIES (
    policy_id, product_line, region, area, vehicle_brand, vehicle_power,
    vehicle_age, vehicle_fuel, driver_age, bonus_malus, density,
    annual_premium, status, start_date, end_date, updated_at
)
SELECT
    s.policy_id, 'AUTO', s.region, s.area, s.vehicle_brand, s.vehicle_power,
    s.vehicle_age, s.vehicle_fuel, s.driver_age, s.bonus_malus, s.density,
    {PREMIUM_FORMULA},
    'ACTIVE',
    {{start_date_expr}} AS start_date,
    DATEADD(year, 1, start_date) AS end_date,  -- same random date, via lateral alias
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
FROM POLICY_SEED_POOL s
WHERE NOT EXISTS (SELECT 1 FROM POLICIES p WHERE p.policy_id = s.policy_id)
ORDER BY s.policy_id
LIMIT %(n)s
"""

# Initial load: spread start dates over the last year.
INITIAL_START_DATE = "DATEADD(day, -UNIFORM(0, 364, RANDOM()), CURRENT_DATE())"
# New business issued by the simulator starts today.
TODAY = "CURRENT_DATE()"

SAMPLE_ACTIVE_POLICIES = """
SELECT policy_id, annual_premium, region
FROM POLICIES
WHERE status = 'ACTIVE'
SAMPLE (%(n)s ROWS)
"""

MAX_ENDORSEMENT_ID = "SELECT COALESCE(MAX(endorsement_id), 0) FROM ENDORSEMENTS"

INSERT_ENDORSEMENT = """
INSERT INTO ENDORSEMENTS (
    endorsement_id, policy_id, endorsement_type, premium_delta, new_region,
    new_vehicle_age, effective_date, batch_id, created_at
) VALUES (
    %(endorsement_id)s, %(policy_id)s, %(endorsement_type)s, %(premium_delta)s,
    %(new_region)s, %(new_vehicle_age)s, CURRENT_DATE(), %(batch_id)s,
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
)
"""

# Apply the batch's endorsements to the policies, overwriting in place,
# the way a legacy OLTP system does.
APPLY_ENDORSEMENTS = """
UPDATE POLICIES p
SET annual_premium = p.annual_premium + e.premium_delta,
    region         = COALESCE(e.new_region, p.region),
    vehicle_age    = COALESCE(e.new_vehicle_age, p.vehicle_age),
    status         = IFF(e.endorsement_type = 'CANCELLATION', 'CANCELLED', p.status),
    end_date       = IFF(e.endorsement_type = 'CANCELLATION', e.effective_date, p.end_date),
    updated_at     = CURRENT_TIMESTAMP()::TIMESTAMP_NTZ
FROM ENDORSEMENTS e
WHERE e.policy_id = p.policy_id
  AND e.batch_id = %(batch_id)s
"""

# Hard delete: a policy issued by mistake is removed by the back office.
# Only policies without endorsements can be removed (referential safety).
DELETE_POLICIES = """
DELETE FROM POLICIES p
WHERE p.policy_id IN ({placeholders})
  AND NOT EXISTS (SELECT 1 FROM ENDORSEMENTS e WHERE e.policy_id = p.policy_id)
"""
