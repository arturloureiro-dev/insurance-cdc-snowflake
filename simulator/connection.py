"""Snowflake connection built from environment variables (key-pair auth)."""

from __future__ import annotations

import os

from dotenv import load_dotenv


def get_connection():
    """Open a Snowflake connection for the service user defined in .env."""
    import snowflake.connector  # imported lazily so unit tests don't need it

    load_dotenv()
    return snowflake.connector.connect(
        account=os.environ["SNOWFLAKE_ACCOUNT"],
        user=os.environ["SNOWFLAKE_USER"],
        authenticator="SNOWFLAKE_JWT",
        private_key_file=os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"],
        role=os.getenv("SNOWFLAKE_ROLE", "CDC_ENGINEER"),
        warehouse=os.getenv("SNOWFLAKE_WAREHOUSE", "WH_CDC"),
        database=os.getenv("SNOWFLAKE_DATABASE", "INSURANCE_CDC"),
        schema="LEGACY",
    )
