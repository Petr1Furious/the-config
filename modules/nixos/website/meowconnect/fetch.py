"""Fetch and preserve raw MeowConnect API responses."""

from __future__ import annotations

import random
import time
from typing import Any, Callable

from .client import MeowConnectClient


def fetch_raw_responses(
    client: MeowConnectClient,
    *,
    select: Callable[[dict], bool] | None = None,
    min_delay: float = 0.3,
    max_delay: float = 0.8,
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Fetch the connection list and the connect response for each gate.

    `select`, when given, limits which gates are actually dialled (the full
    connection list is always kept for config metadata). The credentials the
    backend returns are short-lived, so this runs on demand per request rather
    than on a long cache.
    """
    started = time.time()
    connections = client.list_connections()
    responses: dict[str, Any] = {}
    errors: list[dict[str, Any]] = []

    fetched = 0
    for connection in connections:
        if not isinstance(connection, dict) or not isinstance(connection.get("id"), int):
            continue
        if select is not None and not select(connection):
            continue
        if fetched > 0:
            time.sleep(random.uniform(min_delay, max_delay))
        fetched += 1

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
