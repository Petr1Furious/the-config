"""Fetch and preserve raw MeowConnect API responses."""

from __future__ import annotations

import random
import time
from typing import Any

from .client import MeowConnectClient


def fetch_raw_responses(
    client: MeowConnectClient,
    *,
    min_delay: float = 2.0,
    max_delay: float = 4.0,
) -> tuple[dict[str, Any], dict[str, Any]]:
    started = time.time()
    connections = client.list_connections()
    responses: dict[str, Any] = {}
    errors: list[dict[str, Any]] = []

    for index, connection in enumerate(connections):
        if index > 0:
            time.sleep(random.uniform(min_delay, max_delay))

        gate_id = connection["id"]
        try:
            responses[str(gate_id)] = client.connect(gate_id)
        except Exception as exc:
            errors.append(
                {
                    "gate_id": gate_id,
                    "name": connection.get("name"),
                    "shortname": connection.get("shortname"),
                    "error": str(exc),
                }
            )

    if not responses:
        raise RuntimeError(
            "MeowConnect refresh produced no connect responses"
            + (f"; errors={errors!r}" if errors else "")
        )

    raw = {
        "connections": connections,
        "responses": responses,
    }
    meta = {
        "fetched_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "duration_seconds": round(time.time() - started, 2),
        "connection_count": len(connections),
        "response_count": len(responses),
        "errors": errors,
    }
    return raw, meta
