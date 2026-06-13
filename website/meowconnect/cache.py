"""Persist MeowConnect outbound cache to disk."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


class OutboundCache:
    def __init__(self, state_dir: Path) -> None:
        self.state_dir = state_dir
        self.outbounds_path = state_dir / "outbounds.json"
        self.meta_path = state_dir / "meta.json"

    def ensure_state_dir(self) -> None:
        self.state_dir.mkdir(parents=True, exist_ok=True)

    def exists(self) -> bool:
        return self.outbounds_path.is_file()

    def load_outbounds(self) -> list[dict[str, Any]]:
        with self.outbounds_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, list):
            raise ValueError("cached outbounds must be a JSON array")
        return data

    def load_meta(self) -> dict[str, Any]:
        if not self.meta_path.is_file():
            return {}
        with self.meta_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            raise ValueError("cached meta must be a JSON object")
        return data

    def save(self, outbounds: list[dict[str, Any]], meta: dict[str, Any]) -> None:
        self.ensure_state_dir()
        outbounds_body = json.dumps(outbounds, indent=2, ensure_ascii=False)
        meta_body = json.dumps(meta, indent=2, ensure_ascii=False)
        self.outbounds_path.write_text(outbounds_body + "\n", encoding="utf-8")
        self.meta_path.write_text(meta_body + "\n", encoding="utf-8")
