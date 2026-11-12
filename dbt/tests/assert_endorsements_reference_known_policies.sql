-- Every endorsement in the warehouse must point to a policy that exists or
-- existed (the change log keeps deleted policies too).
select e.endorsement_id, e.policy_id
from {{ ref('fct_endorsements') }} e
left join (select distinct policy_id from {{ ref('stg_policy_changes') }}) p
    on p.policy_id = e.policy_id
where p.policy_id is null
