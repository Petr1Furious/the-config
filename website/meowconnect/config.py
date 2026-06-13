"""Load MeowConnect client settings from environment variables."""

from __future__ import annotations

import os

from .client import ClientConfig

ENV_PREFIX = "MEOWCONNECT_"
REQUIRED_FIELDS = (
    "user_agent",
    "device_name",
    "accept_language",
    "host",
    "content_type",
    "hwid",
    "access_key",
    "accept_encoding",
)


def env_name(field: str) -> str:
    return f"{ENV_PREFIX}{field.upper()}"


def load_client_config() -> ClientConfig:
    values: dict[str, str] = {}
    missing: list[str] = []
    for field in REQUIRED_FIELDS:
        value = os.environ.get(env_name(field), "").strip()
        if not value:
            missing.append(env_name(field))
        else:
            values[field] = value
    if missing:
        raise RuntimeError(
            "Missing required MeowConnect environment variables: "
            + ", ".join(missing)
        )
    return ClientConfig(**values)
