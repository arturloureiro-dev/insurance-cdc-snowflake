-- One row per captured change on an endorsement.
select
    change_id,
    cdc_operation,
    cdc_captured_at,
    endorsement_id,
    policy_id,
    upper(endorsement_type)            as endorsement_type,
    premium_delta::number(12, 2)       as premium_delta,
    new_region                         as new_region_code,
    new_vehicle_age,
    effective_date,
    batch_id,
    created_at
from {{ source('raw', 'endorsement_changes') }}
