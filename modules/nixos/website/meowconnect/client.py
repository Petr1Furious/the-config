"""HTTPS client for MeowConnect public connection endpoints."""

from __future__ import annotations

import gzip
import json
from dataclasses import dataclass, field, replace
from typing import Any, TypedDict
from urllib.error import HTTPError
from urllib.request import Request, urlopen

CONNECTION_BASE_URL = "https://meowconnect.com/api/v1/public/connection"
PROFILE_URL = "https://meowconnect.com/api/v1/public/subscription/profile"


class Gateway(TypedDict):
    name: str
    address: str


class Connection(TypedDict):
    id: int
    name: str
    shortname: str
    icon_url: str
    is_best: bool
    emoji: str
    hide_gateways: bool
    gateways: list[Gateway]
    meta: dict[str, Any]


class ConnectResponse(TypedDict):
    platform: str
    configuration: dict[str, Any]
    expiration_at: str | None


class ProfileResponse(TypedDict):
    data_limit: int
    data_usage: int
    expiration_at: str
    name: str


@dataclass(frozen=True)
class ClientConfig:
    """Headers for authenticated public API endpoints."""

    user_agent: str
    device_name: str
    accept_language: str
    host: str
    content_type: str
    hwid: str
    access_key: str
    accept_encoding: str
    extra_headers: dict[str, str] = field(default_factory=dict)

    def headers(self) -> dict[str, str]:
        headers = {
            "user-agent": self.user_agent,
            "x-device-name": self.device_name,
            "accept-language": self.accept_language,
            "host": self.host,
            "content-type": self.content_type,
            "x-hwid": self.hwid,
            "x-access-key": self.access_key,
            "accept-encoding": self.accept_encoding,
        }
        headers.update(self.extra_headers)
        return headers

    def with_overrides(self, **kwargs: Any) -> ClientConfig:
        return replace(self, **kwargs)


class MeowConnectClient:
    def __init__(self, config: ClientConfig) -> None:
        self.config = config

    def list_connections(self) -> list[Connection]:
        """GET /api/v1/public/connection/list"""
        return self._get_json(f"{CONNECTION_BASE_URL}/list")

    def connect(self, gate_id: int) -> ConnectResponse:
        """GET /api/v1/public/connection/connect?gate_id=<id>"""
        return self._get_json(
            f"{CONNECTION_BASE_URL}/connect",
            {"gate_id": str(gate_id)},
        )

    def profile(self) -> ProfileResponse:
        """GET /api/v1/public/subscription/profile"""
        return self._get_json(PROFILE_URL)

    def _get_json(
        self,
        url: str,
        query: dict[str, str] | None = None,
    ) -> Any:
        _, body = self._request(url, query)
        return json.loads(body.decode("utf-8"))

    def _request(
        self,
        url: str,
        query: dict[str, str] | None = None,
    ) -> tuple[int, bytes]:
        if query:
            params = "&".join(f"{key}={value}" for key, value in query.items())
            url = f"{url}?{params}"

        request = Request(url, method="GET", headers=self.config.headers())
        try:
            with urlopen(request, timeout=30) as response:
                body = response.read()
                encoding = response.headers.get("Content-Encoding", "").lower()
                if "gzip" in encoding:
                    body = gzip.decompress(body)
                return response.status, body
        except HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(
                f"HTTP {exc.code} for {url}: {detail}"
            ) from exc
