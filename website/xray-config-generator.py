#!/usr/bin/env python3
import argparse
import ipaddress
import json
import re
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

PLACEHOLDER_RE = re.compile(r"\{\{(\w+)\}\}")


def is_truthy(val: str | None) -> bool:
    if val is None:
        return False
    return val.lower() in {"1", "true", "yes", "y", "on"}


def first(params: dict[str, list[str]], key: str, default: str | None = ""):
    vals = params.get(key)
    return vals[0] if vals and vals[0] is not None else default


def looks_like_ip(s: str) -> bool:
    try:
        ipaddress.ip_address(s)
        return True
    except Exception:
        return False


def deep_clone(obj):
    return json.loads(json.dumps(obj))


def build_populator(params):
    addr = first(params, "address", "")
    srv = first(params, "serverName", "")
    if (not srv) and addr and (not looks_like_ip(addr)):
        params = dict(params)
        params["serverName"] = [addr]

    def replace_in_string(s: str) -> str:
        def repl(m):
            key = m.group(1)
            vals = params.get(key)
            return vals[0] if vals else ""

        return PLACEHOLDER_RE.sub(repl, s)

    def populate(obj):
        if isinstance(obj, str):
            return replace_in_string(obj)
        if isinstance(obj, dict):
            return {k: populate(v) for k, v in obj.items()}
        if isinstance(obj, list):
            return [populate(v) for v in obj]
        return obj

    return populate


def remove_ads_rule(config):
    rules = config.get("routing", {}).get("rules", [])
    keep = []
    for r in rules:
        if r.get("type") == "field" and r.get("outboundTag") == "block":
            dom = r.get("domain") or []
            if any(isinstance(d, str) and "category-ads-all" in d for d in dom):
                continue
        keep.append(r)
    if "routing" in config:
        config["routing"]["rules"] = keep


def maybe_trim_ru_ip_categories(config, no_community: bool, no_re_filter: bool):
    if not (no_community or no_re_filter):
        return
    rules = config.get("routing", {}).get("rules", [])
    targets = []
    if no_community:
        targets.append("geoip:ru-blocked-community")
    if no_re_filter:
        targets.append("geoip:re-filter")
    for r in rules:
        if r.get("type") != "field":
            continue
        ips = r.get("ip")
        if not isinstance(ips, list):
            continue
        r["ip"] = [x for x in ips if x not in targets]


def reorder_outbounds(config, primary_tag: str | None):
    if not primary_tag:
        return
    outbounds = config.get("outbounds")
    if not isinstance(outbounds, list) or not outbounds:
        return
    primary = [o for o in outbounds if o.get("tag") == primary_tag]
    rest = [o for o in outbounds if o.get("tag") != primary_tag]
    if primary:
        config["outbounds"] = primary + rest


class Handler(BaseHTTPRequestHandler):
    route_path = "/"
    template = None

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path != self.route_path:
            self.send_error(404, "Not Found")
            return

        params = parse_qs(parsed.query, keep_blank_values=True)

        # 1) Fill placeholders (with serverName auto-default inside)
        cfg = deep_clone(self.template)
        cfg = build_populator(params)(cfg)

        # 2) Primary outbound ordering (?primary=proxy|direct)
        primary = (first(params, "primary", "") or "").strip()
        if primary not in {"proxy", "direct", ""}:
            self.send_error(400, "Bad primary value; use proxy or direct")
            return
        reorder_outbounds(cfg, primary if primary else None)

        # 3) Toggle ads blocking (default = block). allow_ads=true => remove rule
        if is_truthy(first(params, "allow_ads", None)):
            remove_ads_rule(cfg)

        # 4) Optionally drop these IP categories (default = include both)
        no_comm = is_truthy(first(params, "no_ru_blocked_community", None))
        no_ref = is_truthy(first(params, "no_re_filter", None))
        maybe_trim_ru_ip_categories(cfg, no_comm, no_ref)

        body = json.dumps(cfg, indent=4, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
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


def main():
    ap = argparse.ArgumentParser(description="XRAY config templating HTTP server")
    ap.add_argument(
        "--file",
        required=True,
        help="Path to base XRAY config (JSON) with {{placeholders}}",
    )
    ap.add_argument("--path", default="/", help="URL path to serve (default: /)")
    ap.add_argument(
        "--host", default="127.0.0.1", help="Bind host (default: 127.0.0.1)"
    )
    ap.add_argument("--port", type=int, default=8080, help="Bind port (default: 8080)")
    args = ap.parse_args()

    try:
        with open(args.file, "r", encoding="utf-8") as f:
            template = json.load(f)
    except Exception as e:
        raise SystemExit(f"Failed to parse JSON {args.file}: {e}")

    Handler.route_path = args.path
    Handler.template = template

    server = HTTPServer((args.host, args.port), Handler)
    print(f"Serving on http://{args.host}:{args.port}{args.path}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
