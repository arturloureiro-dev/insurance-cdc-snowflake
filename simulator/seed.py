"""Load the public freMTPL2 dataset into the legacy system and issue the first policies.

Data source: freMTPL2freq — French Motor Third-Party Liability portfolio,
678,013 policies, published on OpenML (dataset id 41214) and in the
CASdatasets R package. Licence: GPL-2 / public research dataset.

Usage:
    python -m simulator.seed --initial-policies 50000
"""

from __future__ import annotations

import argparse
import logging

import pandas as pd

from simulator import sql
from simulator.connection import get_connection

log = logging.getLogger(__name__)

OPENML_DATASET_ID = 41214

COLUMN_MAP = {
    "IDpol": "POLICY_ID",
    "ClaimNb": "CLAIM_COUNT",
    "Exposure": "EXPOSURE_YEARS",
    "Area": "AREA",
    "VehPower": "VEHICLE_POWER",
    "VehAge": "VEHICLE_AGE",
    "DrivAge": "DRIVER_AGE",
    "BonusMalus": "BONUS_MALUS",
    "VehBrand": "VEHICLE_BRAND",
    "VehGas": "VEHICLE_FUEL",
    "Density": "DENSITY",
    "Region": "REGION",
}


def download_fremtpl2() -> pd.DataFrame:
    """Download freMTPL2freq from OpenML."""
    from sklearn.datasets import fetch_openml

    log.info("Downloading freMTPL2freq from OpenML (id=%s)...", OPENML_DATASET_ID)
    return fetch_openml(data_id=OPENML_DATASET_ID, as_frame=True, parser="auto").frame


def prepare_seed(raw: pd.DataFrame) -> pd.DataFrame:
    """Rename and type the public columns to the legacy schema."""
    df = raw.rename(columns=COLUMN_MAP)[list(COLUMN_MAP.values())].copy()
    for col in ("AREA", "VEHICLE_BRAND", "VEHICLE_FUEL", "REGION"):
        df[col] = df[col].astype(str).str.strip("'\" ")
    for col in ("POLICY_ID", "CLAIM_COUNT", "VEHICLE_POWER", "VEHICLE_AGE",
                "DRIVER_AGE", "BONUS_MALUS", "DENSITY"):
        df[col] = pd.to_numeric(df[col]).astype("int64")
    df["EXPOSURE_YEARS"] = pd.to_numeric(df["EXPOSURE_YEARS"]).round(4)
    return df.drop_duplicates(subset="POLICY_ID").sort_values("POLICY_ID")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--initial-policies", type=int, default=50_000,
                        help="How many policies the legacy system already has on day one.")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

    from snowflake.connector.pandas_tools import write_pandas

    seed = prepare_seed(download_fremtpl2())
    log.info("Prepared %s seed policies", f"{len(seed):,}")

    with get_connection() as conn:
        write_pandas(conn, seed, "POLICY_SEED_POOL", overwrite=True, quote_identifiers=False)
        log.info("Loaded seed pool into LEGACY.POLICY_SEED_POOL")

        query = sql.ISSUE_POLICIES.format(start_date_expr=sql.INITIAL_START_DATE)
        cur = conn.cursor().execute(query, {"n": args.initial_policies})
        log.info("Issued %s initial policies into LEGACY.POLICIES", f"{cur.rowcount:,}")


if __name__ == "__main__":
    main()
