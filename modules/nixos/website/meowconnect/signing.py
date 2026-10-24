"""Request signing for the Sota/MeowConnect public API.

Recovered from the Flutter client (libapp.so): authenticated requests to the
four public endpoints carry

    X-Timestamp: <unix seconds>
    X-Signature: base64( HMAC-SHA256( key, "METHOD:path[?query]:body:timestamp" ) )

The query is included only when non-empty; body is the request payload as a
string ("" for the GETs used here). Verified against captured traffic.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import time


def canonical_string(method: str, path: str, query: str, body: str, ts: int) -> str:
    p = f"{path}?{query}" if query else path
    return f"{method.upper()}:{p}:{body}:{ts}"


def sign(key: bytes, method: str, path: str, query: str = "", body: str = "", ts: int | None = None) -> tuple[int, str]:
    ts = int(time.time()) if ts is None else ts
    msg = canonical_string(method, path, query, body, ts)
    mac = hmac.new(key, msg.encode(), hashlib.sha256).digest()
    return ts, base64.b64encode(mac).decode()


def signing_headers(key: bytes, method: str, path: str, query: str = "", body: str = "", ts: int | None = None) -> dict[str, str]:
    ts, sig = sign(key, method, path, query, body, ts)
    return {"x-timestamp": str(ts), "x-signature": sig}
