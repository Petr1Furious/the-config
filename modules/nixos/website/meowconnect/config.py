"""Load MeowConnect client settings from environment + machine id."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path

from .client import ClientConfig

ENV_PREFIX = "MEOWCONNECT_"
REQUIRED = ("access_key", "signing_key")
DEFAULTS = {
    "user_agent": "Sota Connect (v1.8.11/linux)",
    "accept_language": "en",
    "content_type": "application/json",
    "accept_encoding": "gzip",
    "hosts": "meow5g.com,meowconnect.com,sota.ac",
}


def _env(field: str) -> str:
    return os.environ.get(ENV_PREFIX + field.upper(), "").strip()


def compute_hwid() -> str:
    """x-hwid as the client derives it on Linux: sha256 hex of the machine id."""
    for path in ("/etc/machine-id", "/var/lib/dbus/machine-id"):
        try:
            mid = Path(path).read_text().strip()
        except OSError:
            continue
        if mid:
            return hashlib.sha256(mid.encode()).hexdigest()
    raise RuntimeError("cannot read machine-id to derive x-hwid")


def load_client_config() -> ClientConfig:
    missing = [ENV_PREFIX + f.upper() for f in REQUIRED if not _env(f)]
    if missing:
        raise RuntimeError("Missing required env: " + ", ".join(missing))
    hosts = tuple(
        h.strip() for h in (_env("hosts") or DEFAULTS["hosts"]).split(",") if h.strip()
    )
    return ClientConfig(
        user_agent=_env("user_agent") or DEFAULTS["user_agent"],
        device_name=_env("device_name") or (os.uname().nodename + "_Linux"),
        accept_language=_env("accept_language") or DEFAULTS["accept_language"],
        content_type=_env("content_type") or DEFAULTS["content_type"],
        hwid=_env("hwid") or compute_hwid(),
        access_key=_env("access_key"),
        accept_encoding=_env("accept_encoding") or DEFAULTS["accept_encoding"],
        signing_key=_env("signing_key").encode(),
        hosts=hosts,
    )
