"""Local HTTP cache service for MeowConnect outbounds."""

from __future__ import annotations

import argparse
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlparse

from .cache import OutboundCache
from .client import MeowConnectClient
from .config import load_client_config
from .fetch import fetch_all_outbounds


class CacheService:
    def __init__(self, state_dir: Path) -> None:
        self.cache = OutboundCache(state_dir)
        self.lock = threading.Lock()

    def refresh(self) -> dict:
        with self.lock:
            client = MeowConnectClient(load_client_config())
            outbounds, meta = fetch_all_outbounds(client)
            self.cache.save(outbounds, meta)
            return meta

    def outbounds(self) -> list:
        with self.lock:
            if not self.cache.exists():
                raise FileNotFoundError("outbound cache is empty")
            return self.cache.load_outbounds()

    def status(self) -> dict:
        with self.lock:
            meta = self.cache.load_meta()
            meta["cache_exists"] = self.cache.exists()
            return meta


class Handler(BaseHTTPRequestHandler):
    service: CacheService | None = None

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/outbounds":
            self._json_response(200, self._service().outbounds())
            return
        if parsed.path == "/status":
            self._json_response(200, self._service().status())
            return
        self.send_error(404, "Not Found")

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path == "/refresh":
            try:
                meta = self._service().refresh()
            except Exception as exc:
                self.send_error(500, str(exc))
                return
            self._json_response(200, meta)
            return
        self.send_error(404, "Not Found")

    def _service(self) -> CacheService:
        if self.service is None:
            raise RuntimeError("cache service is not configured")
        return self.service

    def _json_response(self, status: int, payload) -> None:
        body = json.dumps(payload, indent=2, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        print(
            "%s - - [%s] %s"
            % (self.client_address[0], self.log_date_time_string(), format % args)
        )


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="MeowConnect outbound cache HTTP server")
    ap.add_argument(
        "--state-dir",
        default="/var/lib/meowconnect",
        help="Directory for cached outbounds (default: /var/lib/meowconnect)",
    )
    ap.add_argument("--host", default="127.0.0.1", help="Bind host (default: 127.0.0.1)")
    ap.add_argument("--port", type=int, default=18083, help="Bind port (default: 18083)")
    ap.add_argument(
        "--refresh-on-start",
        action="store_true",
        help="Run one refresh before serving if cache is missing",
    )
    args = ap.parse_args(argv)

    service = CacheService(Path(args.state_dir))
    if args.refresh_on_start and not service.cache.exists():
        print("Cache missing; running initial refresh...")
        meta = service.refresh()
        print(
            f"Initial refresh complete: {meta.get('outbound_count', 0)} outbounds "
            f"in {meta.get('duration_seconds', '?')}s"
        )

    Handler.service = service
    server = HTTPServer((args.host, args.port), Handler)
    print(f"Serving MeowConnect cache on http://{args.host}:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
