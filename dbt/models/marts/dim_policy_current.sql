-- Current state of every policy, rebuilt from the change log alone.
-- Should match LEGACY.POLICIES row for row (see the reconciliation test).
select
    policy_id,
    product_line,
    region_code,
    area_code,
    vehicle_brand,
    vehicle_power,
    vehicle_age,
    vehicle_fuel,
    driver_age,
    bonus_malus,
    population_density,
    annual_premium,
    policy_status,
    start_date,
    end_date,
    source_updated_at as last_changed_at
from {{ ref('int_policy_latest_change') }}
where change_type <> 'delete'
