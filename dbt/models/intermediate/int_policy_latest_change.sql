-- The most recent captured change per policy. If that change is a delete,
-- the policy no longer exists in the legacy system.
select *
from {{ ref('stg_policy_changes') }}
qualify row_number() over (
    partition by policy_id
    order by source_updated_at desc, change_id desc
) = 1
