-- One row per captured change on a policy, renamed and typed.
select
    change_id,
    cdc_operation,
    case cdc_operation
        when 'I' then 'insert'
        when 'U' then 'update'
        when 'D' then 'delete'
    end                                   as change_type,
    cdc_captured_at,
    source_updated_at,
    policy_id,
    upper(product_line)                   as product_line,
    region                                as region_code,
    area                                  as area_code,
    vehicle_brand,
    vehicle_power,
    vehicle_age,
    vehicle_fuel,
    driver_age,
    bonus_malus,
    density                               as population_density,
    annual_premium::number(12, 2)         as annual_premium,
    upper(status)                         as policy_status,
    start_date,
    end_date
from {{ source('raw', 'policy_changes') }}
