"""HTTPS client for MeowConnect / Sota public connection endpoints.

The public API host rotates server-side. We mirror the app: probe a list of
candidate hosts with the unauthenticated /heartbeat and use the first live one,
then sign the authenticated endpoints (see signing.py).
"""

from __future__ import annotations

import gzip
import json
from dataclasses import dataclass, field, replace
from typing import Any, TypedDict
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from .signing import signing_headers

API_PREFIX = "/api/v1/public"
HEARTBEAT_PATH = "/heartbeat"
HEARTBEAT_USER_AGENT = "Dart/3.x (dart:io)"


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
    """Everything needed to talk to the public API as the app does."""

    user_agent: str
    device_name: str
    accept_language: str
    content_type: str
    hwid: str
    access_key: str
    accept_encoding: str
    signing_key: bytes
    hosts: tuple[str, ...]
    extra_headers: dict[str, str] = field(default_factory=dict)

    def base_headers(self, host: str) -> dict[str, str]:
        headers = {
            "user-agent": self.user_agent,
            "x-device-name": self.device_name,
            "accept-language": self.accept_language,
            "host": host,
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
        self._host: str | None = None

    # -- host resolution (actualization-lite) --------------------------------

    @property
    def host(self) -> str:
        if self._host is None:
            self._host = self._resolve_host()
        return self._host

    def _resolve_host(self) -> str:
        last_error: Exception | None = None
        for candidate in self.config.hosts:
            try:
                req = Request(
                    f"https://{candidate}{HEARTBEAT_PATH}",
                    method="GET",
                    headers={"host": candidate, "user-agent": HEARTBEAT_USER_AGENT},
                )
                with urlopen(req, timeout=15) as response:
                    if 200 <= response.status < 400:
                        return candidate
            except HTTPError as exc:
                # A reachable host that answers (even 4xx) is still the live API.
                if exc.code < 500:
                    return candidate
                last_error = exc
            except (URLError, OSError) as exc:
                last_error = exc
        raise RuntimeError(
            f"No MeowConnect host reachable (tried {', '.join(self.config.hosts)})"
            + (f": {last_error}" if last_error else "")
        )

    # -- endpoints -----------------------------------------------------------

    def list_connections(self) -> list[Connection]:
        return self._get_json(f"{API_PREFIX}/connection/list")

    def connect(self, gate_id: int) -> ConnectResponse:
        return self._get_json(
            f"{API_PREFIX}/connection/connect",
            {"gate_id": str(gate_id)},
        )

    def profile(self) -> ProfileResponse:
        return self._get_json(f"{API_PREFIX}/subscription/profile")

    # -- transport -----------------------------------------------------------

    def _get_json(self, path: str, query: dict[str, str] | None = None) -> Any:
        _, body = self._request(path, query)
        return json.loads(body.decode("utf-8"))

    def _request(self, path: str, query: dict[str, str] | None = None) -> tuple[int, bytes]:
        host = self.host
        query_string = ""
        if query:
            query_string = "&".join(f"{k}={v}" for k, v in query.items())

        url = f"https://{host}{path}"
        if query_string:
            url = f"{url}?{query_string}"

        headers = self.config.base_headers(host)
        headers.update(
            signing_headers(self.config.signing_key, "GET", path, query_string, "")
        )

        request = Request(url, method="GET", headers=headers)
        try:
            with urlopen(request, timeout=30) as response:
                body = response.read()
                if "gzip" in response.headers.get("Content-Encoding", "").lower():
                    body = gzip.decompress(body)
                return response.status, body
        except HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"HTTP {exc.code} for {url}: {detail}") from exc
