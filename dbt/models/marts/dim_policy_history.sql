-- Slowly changing dimension (type 2): one row per version of a policy.
-- The legacy system overwrites rows in place; the change log lets us rebuild
-- the full history, including policies that were later hard-deleted.
with versions as (
    select
        {{ dbt_utils.generate_surrogate_key(['policy_id', 'change_id']) }} as policy_version_key,
        policy_id,
        change_id,
        change_type,
        region_code,
        vehicle_age,
        annual_premium,
        policy_status,
        source_updated_at as valid_from,
        lead(source_updated_at) over (
            partition by policy_id order by source_updated_at, change_id
        ) as next_valid_from
    from {{ ref('stg_policy_changes') }}
)

select
    policy_version_key,
    policy_id,
    change_id,
    change_type,
    region_code,
    vehicle_age,
    annual_premium,
    policy_status,
    valid_from,
    coalesce(next_valid_from, '9999-12-31'::timestamp_ntz) as valid_to,
    next_valid_from is null and change_type <> 'delete'     as is_current,
    change_type = 'delete'                                  as is_deleted
from versions
