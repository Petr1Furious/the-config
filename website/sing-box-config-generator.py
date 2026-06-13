#!/usr/bin/env python3
import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.error import URLError
from urllib.parse import parse_qs, unquote, urlparse
from urllib.request import urlopen

URLTEST_INTERVAL = "15s"
URLTEST_TOLERANCE = 200


def is_truthy(val: str | None) -> bool:
    if val is None:
        return False
    return val.lower() in {"1", "true", "yes", "y", "on"}


def first(params: dict[str, list[str]], key: str, default: str | None = ""):
    vals = params.get(key)
    return vals[0] if vals and vals[0] is not None else default


def deep_clone(obj):
    return json.loads(json.dumps(obj))


def parse_json_param(params: dict[str, list[str]], key: str, default):
    raw = first(params, key, None)
    if raw is None or raw == "":
        return deep_clone(default)
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Bad JSON in '{key}': {exc.msg}") from exc


def as_outbound_list(raw):
    if raw is None:
        return []
    if isinstance(raw, list):
        return raw
    if isinstance(raw, dict):
        return [raw]
    raise ValueError("'outbounds' must be a JSON object or array")


def uses_meowconnect_source(params: dict[str, list[str]]) -> bool:
    raw = first(params, "outbounds_source", None)
    if raw is None:
        return False
    return (raw or "").strip().lower() == "meowconnect"


def fetch_meowconnect_outbounds(url: str) -> list:
    if not url:
        raise ValueError("MeowConnect outbounds URL is not configured")
    try:
        with urlopen(url, timeout=30) as response:
            body = response.read()
    except URLError as exc:
        raise ValueError(f"Failed to fetch MeowConnect outbounds: {exc}") from exc

    try:
        data = json.loads(body.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"MeowConnect outbounds response is not JSON: {exc.msg}") from exc

    outbounds = as_outbound_list(data)
    if not outbounds:
        raise ValueError("MeowConnect outbounds cache is empty")
    return outbounds


def resolve_outbounds_raw(params: dict[str, list[str]], meowconnect_url: str | None):
    explicit_raw = parse_json_param(params, "outbounds", [])
    explicit = as_outbound_list(explicit_raw)
    use_meow = uses_meowconnect_source(params)

    if use_meow and explicit:
        meow_outbounds = fetch_meowconnect_outbounds(meowconnect_url or "")
        return explicit + meow_outbounds
    if use_meow:
        return fetch_meowconnect_outbounds(meowconnect_url or "")
    if explicit:
        return explicit
    raise ValueError(
        "No proxy outbounds configured. Provide 'outbounds' and/or "
        "'outbounds_source=meowconnect'."
    )


def build_urltest(tag: str, outbounds: list[str]):
    return {
        "type": "urltest",
        "tag": tag,
        "outbounds": outbounds,
        "url": "https://cp.cloudflare.com/generate_204",
        "interval": URLTEST_INTERVAL,
        "tolerance": URLTEST_TOLERANCE,
        "interrupt_exist_connections": False,
    }


PROXY_REF_KEYS = frozenset({"outbound", "detour", "download_detour"})


def build_proxy_outbounds(raw, include_selector: bool = True):
    provided_outbounds = as_outbound_list(raw)
    if not provided_outbounds:
        raise ValueError(
            "No proxy outbounds configured. Provide JSON in query param 'outbounds'."
        )

    proxy_outbounds = []
    tags = []
    for index, raw_outbound in enumerate(provided_outbounds, start=1):
        if not isinstance(raw_outbound, dict):
            raise ValueError("Each outbound must be a JSON object")

        outbound = deep_clone(raw_outbound)
        tag = outbound.get("tag")
        if tag is None or (isinstance(tag, str) and not tag.strip()):
            tag = f"proxy-s{index}"
            outbound["tag"] = tag
        if not isinstance(tag, str) or not tag.strip():
            raise ValueError(f"Outbound #{index} must have a string 'tag'")

        tags.append(tag)
        proxy_outbounds.append(outbound)

    generated = proxy_outbounds + [build_urltest("proxy-auto", tags)]
    if include_selector:
        generated.append(
            {
                "type": "selector",
                "tag": "proxy",
                "outbounds": ["proxy-auto"] + tags,
                "default": "proxy-auto",
            }
        )
    return generated


def outbound_tags(outbounds: list) -> set[str]:
    tags: set[str] = set()
    for outbound in outbounds:
        if isinstance(outbound, dict):
            tag = outbound.get("tag")
            if isinstance(tag, str) and tag:
                tags.add(tag)
    return tags


def validate_fixed_outbound(tag: str, generated_outbounds: list):
    allowed = outbound_tags(generated_outbounds)
    if tag not in allowed:
        raise ValueError(
            f"'fixed_outbound' must be a generated outbound tag; got '{tag}'. "
            f"Available: {', '.join(sorted(allowed))}"
        )


def replace_proxy_references(obj, fixed_tag: str):
    if isinstance(obj, dict):
        replaced = {}
        for key, value in obj.items():
            if key in PROXY_REF_KEYS and value == "proxy":
                replaced[key] = fixed_tag
            elif key == "final" and value == "proxy":
                replaced[key] = fixed_tag
            else:
                replaced[key] = replace_proxy_references(value, fixed_tag)
        return replaced
    if isinstance(obj, list):
        return [replace_proxy_references(item, fixed_tag) for item in obj]
    return obj


def apply_fixed_outbound(config, fixed_tag: str):
    dns = config.get("dns")
    if isinstance(dns, dict):
        config["dns"] = replace_proxy_references(dns, fixed_tag)
    route = config.get("route")
    if isinstance(route, dict):
        config["route"] = replace_proxy_references(route, fixed_tag)


def set_generated_outbounds(config, generated_outbounds):
    outbounds = config.get("outbounds")
    if not isinstance(outbounds, list):
        outbounds = []

    base_outbounds = []
    for outbound in outbounds:
        if not isinstance(outbound, dict):
            continue
        if outbound.get("tag") in {"proxy", "proxy-auto"}:
            continue
        base_outbounds.append(outbound)

    config["outbounds"] = base_outbounds + generated_outbounds


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


def set_route_final(config, final: str | None):
    if not final:
        return
    route = config.get("route")
    if isinstance(route, dict):
        route["final"] = final


def resolve_route_final(primary: str, fixed_outbound: str | None) -> str:
    if primary == "proxy" and fixed_outbound:
        return fixed_outbound
    return primary


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

    selected_inbound_tags = {
        inbound.get("tag")
        for inbound in config.get("inbounds", [])
        if isinstance(inbound, dict)
        and isinstance(inbound.get("tag"), str)
        and inbound.get("tag")
    }
    trim_route_rules_for_inbounds(config, selected_inbound_tags)


def set_proxy_inbounds_listen(config, listen: str):
    inbounds = config.get("inbounds")
    if not isinstance(inbounds, list):
        return
    for inbound in inbounds:
        if isinstance(inbound, dict) and inbound.get("type") in {"socks", "http"}:
            inbound["listen"] = listen


def _filter_rule_inbound_value(value, selected_tags: set[str]):
    if isinstance(value, str):
        return value if value in selected_tags else None
    if isinstance(value, list):
        kept = [x for x in value if isinstance(x, str) and x in selected_tags]
        return kept if kept else None
    return value


def trim_route_rules_for_inbounds(config, selected_tags: set[str]):
    route = config.get("route")
    if not isinstance(route, dict):
        return
    rules = route.get("rules")
    if not isinstance(rules, list):
        return
    if not selected_tags:
        return

    trimmed_rules = []
    for rule in rules:
        if not isinstance(rule, dict):
            trimmed_rules.append(rule)
            continue

        if "inbound" not in rule:
            trimmed_rules.append(rule)
            continue

        filtered = _filter_rule_inbound_value(rule.get("inbound"), selected_tags)
        if filtered is None:
            continue

        new_rule = dict(rule)
        new_rule["inbound"] = filtered
        trimmed_rules.append(new_rule)

    route["rules"] = trimmed_rules


class Handler(BaseHTTPRequestHandler):
    route_path = "/"
    shortcut_dir = Path("/srv/sing-box-generator")
    templates = {}
    meowconnect_url = None

    def do_GET(self):
        parsed = urlparse(self.path)
        try:
            params = self.resolve_params(parsed)
        except FileNotFoundError:
            self.send_error(404, "Not Found")
            return
        except ValueError as exc:
            self.send_error(400, str(exc))
            return

        template_key = "legacy" if is_truthy(first(params, "legacy", None)) else "default"
        template = self.templates.get(template_key)
        if template is None:
            self.send_error(400, "Legacy config template is not configured")
            return

        cfg = deep_clone(template)
        fixed_outbound = None
        try:
            outbounds_raw = resolve_outbounds_raw(params, self.meowconnect_url)
            fixed_outbound_raw = first(params, "fixed_outbound", None)
            fixed_outbound = (
                (fixed_outbound_raw or "").strip() if fixed_outbound_raw is not None else None
            ) or None
            generated_outbounds = build_proxy_outbounds(
                outbounds_raw,
                include_selector=fixed_outbound is None,
            )
            if fixed_outbound:
                validate_fixed_outbound(fixed_outbound, generated_outbounds)
            set_generated_outbounds(cfg, generated_outbounds)
            if fixed_outbound:
                apply_fixed_outbound(cfg, fixed_outbound)
        except ValueError as exc:
            self.send_error(400, str(exc))
            return

        primary_raw = first(params, "primary", "direct")
        primary = (primary_raw or "direct").strip().lower()
        if primary not in {"proxy", "direct"}:
            self.send_error(400, "Bad primary value; use proxy or direct")
            return
        route_final = resolve_route_final(primary, fixed_outbound)
        reorder_tag = route_final if primary == "proxy" else primary
        reorder_outbounds(cfg, reorder_tag)
        set_route_final(cfg, route_final)

        inbound_raw = first(params, "inbound", "tun")
        inbound_mode = (inbound_raw or "tun").strip().lower()
        if inbound_mode not in {"tun", "proxy"}:
            self.send_error(400, "Bad inbound value; use tun or proxy")
            return
        set_inbounds(cfg, inbound_mode)

        if is_truthy(first(params, "proxy_public", None)):
            set_proxy_inbounds_listen(cfg, "0.0.0.0")

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

    def resolve_params(self, parsed):
        request_params = parse_qs(parsed.query, keep_blank_values=True)
        if parsed.path == self.route_path:
            return request_params

        shortcut_params = self.load_shortcut_params(parsed.path)
        shortcut_params.update(request_params)
        return shortcut_params

    def load_shortcut_params(self, request_path: str):
        shortcut_path = self.shortcut_path_for(request_path)
        with shortcut_path.open("r", encoding="utf-8") as f:
            content = f.read().strip()
        if content.startswith("?"):
            content = content[1:]
        return parse_qs(content, keep_blank_values=True)

    def shortcut_path_for(self, request_path: str):
        route_prefix = self.route_path.rsplit("/", 1)[0]
        if not request_path.startswith(route_prefix + "/"):
            raise FileNotFoundError

        relative = unquote(request_path[len(route_prefix) + 1 :])
        if not relative or relative.startswith("/") or "\x00" in relative:
            raise FileNotFoundError

        root = self.shortcut_dir.resolve()
        candidate = (root / relative).resolve()
        if root != candidate and root not in candidate.parents:
            raise FileNotFoundError
        if not candidate.is_file():
            raise FileNotFoundError
        return candidate

    def log_message(self, format, *args):
        print(
            "%s - - [%s] %s"
            % (self.client_address[0], self.log_date_time_string(), format % args)
        )


def load_json(path: str):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        raise SystemExit(f"Failed to parse JSON {path}: {e}")


def main():
    ap = argparse.ArgumentParser(description="sing-box config templating HTTP server")
    ap.add_argument("--file", required=True, help="Path to base sing-box config (JSON)")
    ap.add_argument("--legacy-file", help="Path to legacy base sing-box config (JSON)")
    ap.add_argument(
        "--shortcut-dir",
        default="/srv/sing-box-generator",
        help="Directory with query-string shortcut files (default: /srv/sing-box-generator)",
    )
    ap.add_argument("--path", default="/", help="URL path to serve (default: /)")
    ap.add_argument(
        "--host", default="127.0.0.1", help="Bind host (default: 127.0.0.1)"
    )
    ap.add_argument("--port", type=int, default=8080, help="Bind port (default: 8080)")
    ap.add_argument(
        "--meowconnect-url",
        help="URL for cached MeowConnect outbounds (e.g. http://127.0.0.1:18083/outbounds)",
    )
    args = ap.parse_args()

    Handler.route_path = args.path
    Handler.shortcut_dir = Path(args.shortcut_dir)
    Handler.meowconnect_url = args.meowconnect_url
    Handler.templates = {"default": load_json(args.file)}
    if args.legacy_file:
        Handler.templates["legacy"] = load_json(args.legacy_file)

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
