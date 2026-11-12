import random

import pandas as pd
import pytest

from simulator.legacy_simulator import (
    DEFAULT_MIX,
    REGIONS,
    Policy,
    make_endorsement,
    plan_batch,
    split_events,
)
from simulator.seed import prepare_seed


def _policies(n: int) -> list[Policy]:
    return [Policy(policy_id=i, annual_premium=500.0, region="R11") for i in range(1, n + 1)]


def test_split_events_adds_up():
    counts = split_events(997, DEFAULT_MIX)
    assert sum(counts.values()) == 997
    assert counts["DELETE"] == int(997 * 0.03)


def test_split_events_rejects_bad_mix():
    with pytest.raises(ValueError):
        split_events(100, {"NEW_POLICY": 0.5})


def test_plan_batch_total_matches_requested_events():
    plan = plan_batch(_policies(1000), 500, random.Random(1))
    assert plan.total_events == 500


def test_each_policy_touched_at_most_once_per_batch():
    plan = plan_batch(_policies(1000), 500, random.Random(2))
    touched = [e["policy_id"] for e in plan.endorsements] + plan.deletes
    assert len(touched) == len(set(touched))


def test_without_existing_policies_everything_is_new_business():
    plan = plan_batch([], 200, random.Random(3))
    assert plan.new_policies == 200
    assert plan.endorsements == [] and plan.deletes == []


def test_plan_is_deterministic_for_a_given_seed():
    a = plan_batch(_policies(300), 100, random.Random(42))
    b = plan_batch(_policies(300), 100, random.Random(42))
    assert a == b


@pytest.mark.parametrize("kind", ["PREMIUM_ADJUSTMENT", "VEHICLE_CHANGE", "ADDRESS_CHANGE", "CANCELLATION"])
def test_endorsement_never_makes_premium_negative(kind):
    rng = random.Random(7)
    policy = Policy(1, 400.0, "R11")
    for _ in range(1000):
        e = make_endorsement(policy, kind, rng)
        assert policy.annual_premium + e["premium_delta"] > 0


def test_address_change_moves_to_a_different_valid_region():
    e = make_endorsement(Policy(1, 400.0, "R11"), "ADDRESS_CHANGE", random.Random(5))
    assert e["new_region"] in REGIONS and e["new_region"] != "R11"


def test_cancellation_is_a_refund():
    e = make_endorsement(Policy(1, 400.0, "R11"), "CANCELLATION", random.Random(5))
    assert e["premium_delta"] < 0


def test_prepare_seed_maps_and_cleans_public_columns():
    raw = pd.DataFrame({
        "IDpol": [2.0, 1.0, 1.0], "ClaimNb": [0, 1, 1], "Exposure": [0.1, 0.77, 0.77],
        "Area": ["'D'", "'B'", "'B'"], "VehPower": [5, 6, 6], "VehAge": [0, 2, 2],
        "DrivAge": [55, 46, 46], "BonusMalus": [50, 50, 50], "VehBrand": ["'B12'", "B6", "B6"],
        "VehGas": ["'Regular'", "Diesel", "Diesel"], "Density": [1217, 76, 76],
        "Region": ["'R82'", "R72", "R72"],
    })
    seed = prepare_seed(raw)
    assert list(seed["POLICY_ID"]) == [1, 2]          # deduplicated and sorted
    assert seed.loc[seed.POLICY_ID == 2, "AREA"].item() == "D"  # quotes stripped
    assert seed["POLICY_ID"].dtype == "int64"
