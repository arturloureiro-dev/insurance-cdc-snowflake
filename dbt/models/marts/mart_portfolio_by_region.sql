-- Portfolio KPIs per region and product line, ready for a BI tool.
with policies as (
    select * from {{ ref('dim_policy_current') }}
),

endorsements as (
    select
        policy_id,
        count(*)                                                    as endorsement_count,
        count_if(endorsement_type = 'CANCELLATION')                 as cancellation_count
    from {{ ref('fct_endorsements') }}
    group by policy_id
)

select
    p.region_code,
    p.product_line,
    count(*)                                                        as policies,
    count_if(p.policy_status = 'ACTIVE')                            as active_policies,
    count_if(p.policy_status = 'CANCELLED')                         as cancelled_policies,
    round(sum(iff(p.policy_status = 'ACTIVE', p.annual_premium, 0)), 2) as active_written_premium,
    round(avg(p.annual_premium), 2)                                 as avg_annual_premium,
    round(avg(p.bonus_malus), 1)                                    as avg_bonus_malus,
    coalesce(sum(e.endorsement_count), 0)                           as endorsements,
    round(div0(count_if(p.policy_status = 'CANCELLED'), count(*)), 4) as cancellation_rate
from policies p
left join endorsements e on e.policy_id = p.policy_id
group by 1, 2
