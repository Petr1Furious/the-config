"""Fetch unified sing-box outbounds from MeowConnect."""

from __future__ import annotations

import json
import random
import time
from typing import Any

from .client import Connection, MeowConnectClient

SKIP_OUTBOUND_TYPES = frozenset({"direct", "block", "dns"})


def extract_proxy_outbound(configuration: dict[str, Any]) -> dict[str, Any]:
    outbounds = configuration.get("outbounds")
    if not isinstance(outbounds, list):
        raise ValueError("connect response missing outbounds list")

    for outbound in outbounds:
        if not isinstance(outbound, dict):
            continue
        outbound_type = outbound.get("type")
        if outbound_type in SKIP_OUTBOUND_TYPES:
            continue
        return json.loads(json.dumps(outbound))
    raise ValueError("connect response missing proxy outbound")


def _sanitize_tag_part(value: str, fallback: str) -> str:
    safe = "".join(ch if ch.isalnum() or ch in "-_" else "-" for ch in value.strip())
    safe = "-".join(part for part in safe.split("-") if part)
    return safe or fallback


def _label_for_connection(connection: Connection) -> str:
    gate_id = str(connection["id"])
    name = str(connection.get("name", "")).strip()
    if name:
        return _sanitize_tag_part(name, gate_id)
    shortname = str(connection.get("shortname", "")).strip()
    if shortname:
        return _sanitize_tag_part(shortname, gate_id)
    return gate_id


def _base_tag_for_connection(connection: Connection) -> str:
    return f"meow-{_label_for_connection(connection)}"


def outbound_tags_for_connections(connections: list[Connection]) -> dict[int, str]:
    base_tags = {connection["id"]: _base_tag_for_connection(connection) for connection in connections}
    grouped: dict[str, list[int]] = {}
    for gate_id, tag in base_tags.items():
        grouped.setdefault(tag, []).append(gate_id)

    tags: dict[int, str] = {}
    for base_tag, gate_ids in grouped.items():
        if len(gate_ids) == 1:
            tags[gate_ids[0]] = base_tag
            continue
        for gate_id in gate_ids:
            tags[gate_id] = f"{base_tag}-{gate_id}"
    return tags


def outbound_tag_for_connection(connection: Connection, tags_by_id: dict[int, str] | None = None) -> str:
    if tags_by_id is not None:
        return tags_by_id[connection["id"]]
    return outbound_tags_for_connections([connection])[connection["id"]]


def fetch_all_outbounds(
    client: MeowConnectClient,
    *,
    min_delay: float = 2.0,
    max_delay: float = 4.0,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    started = time.time()
    connections = client.list_connections()
    tags_by_id = outbound_tags_for_connections(connections)
    outbounds: list[dict[str, Any]] = []
    errors: list[dict[str, Any]] = []

    for index, connection in enumerate(connections):
        if index > 0:
            time.sleep(random.uniform(min_delay, max_delay))

        gate_id = connection["id"]
        try:
            response = client.connect(gate_id)
            configuration = response.get("configuration")
            if not isinstance(configuration, dict):
                raise ValueError("connect response missing configuration object")
            outbound = extract_proxy_outbound(configuration)
            outbound["tag"] = outbound_tag_for_connection(connection, tags_by_id)
            outbounds.append(outbound)
        except Exception as exc:
            errors.append(
                {
                    "gate_id": gate_id,
                    "name": connection.get("name"),
                    "shortname": connection.get("shortname"),
                    "error": str(exc),
                }
            )

    if not outbounds:
        raise RuntimeError(
            "MeowConnect refresh produced no outbounds"
            + (f"; errors={errors!r}" if errors else "")
        )

    meta = {
        "fetched_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "duration_seconds": round(time.time() - started, 2),
        "connection_count": len(connections),
        "outbound_count": len(outbounds),
        "errors": errors,
    }
    return outbounds, meta
