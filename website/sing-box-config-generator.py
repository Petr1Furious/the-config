#!/usr/bin/env python3
import argparse
import ipaddress
import json
import re
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

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


def _rule_has_set(rule, target: str) -> bool:
    rs = rule.get("rule_set")
    if isinstance(rs, list):
        return any(isinstance(x, str) and x == target for x in rs)
    if isinstance(rs, str):
        return rs == target
    return False


def remove_ads_rule(config):
    dns = config.get("dns")
    if isinstance(dns, dict):
        rules = dns.get("rules")
        if isinstance(rules, list):
            dns["rules"] = [r for r in rules if not _rule_has_set(r, "category-ads-all")]

    route = config.get("route")
    if isinstance(route, dict):
        rules = route.get("rules")
        if isinstance(rules, list):
            route["rules"] = [r for r in rules if not _rule_has_set(r, "category-ads-all")]


def maybe_trim_ru_ip_categories(config, no_community: bool, no_re_filter: bool):
    if not (no_community or no_re_filter):
        return

    targets: list[str] = []
    if no_community:
        targets.append("geoip-ru-blocked-community")
    if no_re_filter:
        targets.append("geoip-re-filter")

    if not targets:
        return

    route = config.get("route")
    if not isinstance(route, dict):
        return

    rules = route.get("rules")
    if not isinstance(rules, list):
        return

    trimmed_rules = []
    for rule in rules:
        rs = rule.get("rule_set")
        if isinstance(rs, list):
            new_rs = [x for x in rs if x not in targets]
            if not new_rs and rs:
                continue
            new_rule = dict(rule)
            new_rule["rule_set"] = new_rs
            trimmed_rules.append(new_rule)
        else:
            trimmed_rules.append(rule)

    route["rules"] = trimmed_rules


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


def set_route_final(config, primary: str | None):
    if primary not in {"proxy", "direct"}:
        return
    route = config.get("route")
    if isinstance(route, dict):
        route["final"] = primary


def set_inbounds(config, mode: str):
    inbounds = config.get("inbounds")
    if not isinstance(inbounds, list):
        return

    target_mode = mode.lower()
    if target_mode == "proxy":
        allowed_types = {"socks", "http"}
    else:
        allowed_types = {"tun"}

    selected: list[dict] = []
    for inbound in inbounds:
        if not isinstance(inbound, dict):
            continue
        if inbound.get("type") in allowed_types:
            selected.append(dict(inbound))

    if selected:
        config["inbounds"] = selected
    else:
        config["inbounds"] = [
            dict(inbound) if isinstance(inbound, dict) else inbound for inbound in inbounds
        ]


class Handler(BaseHTTPRequestHandler):
    route_path = "/"
    template = None

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path != self.route_path:
            self.send_error(404, "Not Found")
            return

        params = parse_qs(parsed.query, keep_blank_values=True)

        cfg = deep_clone(self.template)
        cfg = build_populator(params)(cfg)

        primary_raw = first(params, "primary", "direct")
        primary = (primary_raw or "direct").strip().lower()
        if primary not in {"proxy", "direct"}:
            self.send_error(400, "Bad primary value; use proxy or direct")
            return
        reorder_outbounds(cfg, primary)
        set_route_final(cfg, primary)

        inbound_raw = first(params, "inbound", "tun")
        inbound_mode = (inbound_raw or "tun").strip().lower()
        if inbound_mode not in {"tun", "proxy"}:
            self.send_error(400, "Bad inbound value; use tun or proxy")
            return
        set_inbounds(cfg, inbound_mode)

        if is_truthy(first(params, "allow_ads", None)):
            remove_ads_rule(cfg)

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
    ap = argparse.ArgumentParser(description="sing-box config templating HTTP server")
    ap.add_argument(
        "--file",
        required=True,
        help="Path to base sing-box config (JSON) with {{placeholders}}",
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
