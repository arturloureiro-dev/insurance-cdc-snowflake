-- Reconciliation: the state rebuilt from the change log must match the legacy
-- system. Returns policies that differ. Warn-only, because the Task runs every
-- minute and the newest changes may not be captured yet.
{{ config(severity='warn') }}

with legacy as (
    select policy_id, annual_premium, status as policy_status
    from {{ source('legacy', 'policies') }}
),

rebuilt as (
    select policy_id, annual_premium, policy_status
    from {{ ref('dim_policy_current') }}
)

select
    coalesce(l.policy_id, r.policy_id) as policy_id,
    l.annual_premium                   as legacy_premium,
    r.annual_premium                   as rebuilt_premium,
    l.policy_status                    as legacy_status,
    r.policy_status                    as rebuilt_status
from legacy l
full outer join rebuilt r on r.policy_id = l.policy_id
where l.policy_id is null
   or r.policy_id is null
   or l.annual_premium <> r.annual_premium
   or l.policy_status  <> r.policy_status
