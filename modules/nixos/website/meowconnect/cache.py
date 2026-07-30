"""Persist raw MeowConnect API responses to disk."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


class RawResponseCache:
    def __init__(self, state_dir: Path) -> None:
        self.state_dir = state_dir
        self.raw_path = state_dir / "raw-responses.json"
        self.meta_path = state_dir / "meta.json"

    def ensure_state_dir(self) -> None:
        self.state_dir.mkdir(parents=True, exist_ok=True)

    def exists(self) -> bool:
        return self.raw_path.is_file()

    def load_raw(self) -> dict[str, Any]:
        with self.raw_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            raise ValueError("raw MeowConnect cache must be a JSON object")
        if not isinstance(data.get("connections"), list):
            raise ValueError("raw MeowConnect cache is missing the connection list")
        if not isinstance(data.get("responses"), dict):
            raise ValueError("raw MeowConnect cache is missing connect responses")
        return data

    def load_meta(self) -> dict[str, Any]:
        if not self.meta_path.is_file():
            return {}
        with self.meta_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            raise ValueError("cached meta must be a JSON object")
        return data

    def save(self, raw: dict[str, Any], meta: dict[str, Any]) -> None:
        self.ensure_state_dir()
        self._atomic_write(self.raw_path, raw)
        self._atomic_write(self.meta_path, meta)

    @staticmethod
    def _atomic_write(path: Path, value: Any) -> None:
        temporary = path.with_name(f".{path.name}.tmp")
        body = json.dumps(value, indent=2, ensure_ascii=False)
        temporary.write_text(body + "\n", encoding="utf-8")
        temporary.replace(path)
