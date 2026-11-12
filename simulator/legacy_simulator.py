"""Simulate day-to-day traffic in the legacy insurance system.

Each batch mixes the operations a policy administration system really does:
  - new business        -> INSERT into POLICIES
  - endorsements        -> INSERT into ENDORSEMENTS + UPDATE of the policy
  - cancellations       -> endorsement + UPDATE status to CANCELLED
  - back-office fixes   -> hard DELETE of a policy issued by mistake

Snowflake Streams pick these changes up without the simulator knowing anything
about them, which is the point: the legacy system keeps working as before.

Usage:
    python -m simulator.legacy_simulator --events-per-batch 500 --batches 20 --interval-seconds 30
"""

from __future__ import annotations

import argparse
import logging
import random
import time
import uuid
from dataclasses import dataclass, field

from simulator import sql

log = logging.getLogger(__name__)

# French administrative region codes as used in freMTPL2.
REGIONS = [
    "R11", "R21", "R22", "R23", "R24", "R25", "R26", "R31", "R41", "R42", "R43",
    "R52", "R53", "R54", "R72", "R73", "R74", "R82", "R83", "R91", "R93", "R94",
]

# Share of each operation in a batch (must sum to 1).
DEFAULT_MIX = {
    "NEW_POLICY": 0.30,
    "PREMIUM_ADJUSTMENT": 0.30,
    "VEHICLE_CHANGE": 0.15,
    "ADDRESS_CHANGE": 0.10,
    "CANCELLATION": 0.12,
    "DELETE": 0.03,
}


@dataclass(frozen=True)
class Policy:
    policy_id: int
    annual_premium: float
    region: str


@dataclass
class BatchPlan:
    batch_id: str
    new_policies: int = 0
    endorsements: list[dict] = field(default_factory=list)
    deletes: list[int] = field(default_factory=list)

    @property
    def total_events(self) -> int:
        return self.new_policies + len(self.endorsements) + len(self.deletes)


def split_events(n_events: int, mix: dict[str, float]) -> dict[str, int]:
    """Turn a total number of events into a count per operation type."""
    if abs(sum(mix.values()) - 1) > 1e-9:
        raise ValueError("mix shares must sum to 1")
    counts = {op: int(n_events * share) for op, share in mix.items()}
    counts["NEW_POLICY"] += n_events - sum(counts.values())  # rounding remainder
    return counts


def make_endorsement(policy: Policy, kind: str, rng: random.Random) -> dict:
    """Build one endorsement for a policy. Premium never goes negative."""
    premium = float(policy.annual_premium)
    new_region = None
    new_vehicle_age = None
    if kind == "PREMIUM_ADJUSTMENT":
        delta = premium * rng.uniform(-0.10, 0.15)
    elif kind == "VEHICLE_CHANGE":
        new_vehicle_age = rng.randint(0, 5)
        delta = premium * rng.uniform(0.0, 0.20)
    elif kind == "ADDRESS_CHANGE":
        new_region = rng.choice([r for r in REGIONS if r != policy.region])
        delta = premium * rng.uniform(-0.05, 0.10)
    elif kind == "CANCELLATION":
        delta = -premium * rng.uniform(0.20, 0.80)  # pro-rata refund
    else:
        raise ValueError(f"unknown endorsement type: {kind}")
    return {
        "policy_id": policy.policy_id,
        "endorsement_type": kind,
        "premium_delta": round(delta, 2),
        "new_region": new_region,
        "new_vehicle_age": new_vehicle_age,
    }


def plan_batch(
    active: list[Policy],
    n_events: int,
    rng: random.Random,
    mix: dict[str, float] | None = None,
) -> BatchPlan:
    """Decide what the batch will do. Pure function: no database access.

    Each existing policy is touched at most once per batch, so every change
    in the batch is unambiguous.
    """
    counts = split_events(n_events, mix or DEFAULT_MIX)
    plan = BatchPlan(batch_id=str(uuid.UUID(int=rng.getrandbits(128))))

    pool = list(active)
    rng.shuffle(pool)

    for kind in ("PREMIUM_ADJUSTMENT", "VEHICLE_CHANGE", "ADDRESS_CHANGE", "CANCELLATION"):
        for _ in range(counts[kind]):
            if not pool:
                break
            plan.endorsements.append(make_endorsement(pool.pop(), kind, rng))

    plan.deletes = [pool.pop().policy_id for _ in range(min(counts["DELETE"], len(pool)))]
    # Events that found no existing policy become new business instead.
    plan.new_policies = n_events - len(plan.endorsements) - len(plan.deletes)
    return plan


def fetch_active_policies(conn, n: int) -> list[Policy]:
    rows = conn.cursor().execute(sql.SAMPLE_ACTIVE_POLICIES, {"n": n}).fetchall()
    return [Policy(int(r[0]), float(r[1]), r[2]) for r in rows]


def apply_plan(conn, plan: BatchPlan) -> None:
    """Run the batch against the legacy tables, like the legacy app would."""
    cur = conn.cursor()

    if plan.new_policies:
        cur.execute(sql.ISSUE_POLICIES.format(start_date_expr=sql.TODAY), {"n": plan.new_policies})

    if plan.endorsements:
        next_id = cur.execute(sql.MAX_ENDORSEMENT_ID).fetchone()[0] + 1
        rows = [
            {**e, "endorsement_id": next_id + i, "batch_id": plan.batch_id}
            for i, e in enumerate(plan.endorsements)
        ]
        cur.executemany(sql.INSERT_ENDORSEMENT, rows)
        cur.execute(sql.APPLY_ENDORSEMENTS, {"batch_id": plan.batch_id})

    if plan.deletes:
        placeholders = ", ".join(["%s"] * len(plan.deletes))
        cur.execute(sql.DELETE_POLICIES.format(placeholders=placeholders), plan.deletes)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--events-per-batch", type=int, default=500)
    parser.add_argument("--batches", type=int, default=10)
    parser.add_argument("--interval-seconds", type=float, default=30)
    parser.add_argument("--seed", type=int, default=None, help="Random seed for repeatable runs.")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    from simulator.connection import get_connection

    rng = random.Random(args.seed)
    per_day = args.events_per_batch * 86_400 / max(args.interval_seconds, 1)
    log.info("Simulating ~%s documents/day", f"{per_day:,.0f}")

    with get_connection() as conn:
        for i in range(1, args.batches + 1):
            active = fetch_active_policies(conn, args.events_per_batch)
            plan = plan_batch(active, args.events_per_batch, rng)
            apply_plan(conn, plan)
            log.info(
                "Batch %s/%s %s: %s new, %s endorsements, %s deletes",
                i, args.batches, plan.batch_id[:8], plan.new_policies,
                len(plan.endorsements), len(plan.deletes),
            )
            if i < args.batches:
                time.sleep(args.interval_seconds)


if __name__ == "__main__":
    main()
