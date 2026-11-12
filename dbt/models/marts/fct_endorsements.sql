{{ config(
    materialized='incremental',
    unique_key='endorsement_id',
    incremental_strategy='merge'
) }}

-- One row per endorsement. Incremental: each run only reads changes captured
-- since the last run, then merges them on endorsement_id.
select
    e.endorsement_id,
    e.policy_id,
    e.endorsement_type,
    e.premium_delta,
    e.new_region_code,
    e.new_vehicle_age,
    e.effective_date,
    e.batch_id,
    e.created_at,
    e.cdc_captured_at
from {{ ref('stg_endorsement_changes') }} e
where e.cdc_operation <> 'D'
{% if is_incremental() %}
  and e.cdc_captured_at > (select coalesce(max(cdc_captured_at), '1900-01-01') from {{ this }})
{% endif %}
qualify row_number() over (partition by e.endorsement_id order by e.change_id desc) = 1
