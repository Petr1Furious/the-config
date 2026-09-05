#!/usr/bin/env python3
import argparse
import ipaddress
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlparse

from meowconnect.cache import RawResponseCache
from meowconnect.client import MeowConnectClient
from meowconnect.config import load_client_config
from meowconnect.fetch import fetch_raw_responses

URLTEST_INTERVAL = "3m"
URLTEST_TOLERANCE = 200
AUTOMATIC_OUTBOUND_TAG = "Automatic"
SKIP_OUTBOUND_TYPES = frozenset({"direct", "block", "dns", "selector", "urltest"})
RUSSIAN_SERVER_NAME = "russia"
ROUTING_MODES = frozenset({"all-except-ru", "all-including-ru", "blocked", "ru-only"})

RU_DIRECT_RULE_SETS = frozenset({"geosite-ru-available-only-inside", "geoip-ru"})
RU_DOMAIN_SUFFIXES = ("ru", "su", "xn--p1ai", "moscow", "xn--80adxhks", "xn--p1acf")


def is_truthy(val: str | None) -> bool:
    if val is None:
        return False
    return val.lower() in {"1", "true", "yes", "y", "on"}


def first(params: dict[str, list[str]], key: str, default: str | None = ""):
    vals = params.get(key)
    return vals[0] if vals and vals[0] is not None else default


def deep_clone(obj):
    return json.loads(json.dumps(obj))


def normalize_server_name(value: str) -> str:
    return " ".join(
        "".join(char.lower() if char.isalnum() else " " for char in value).split()
    )


def parse_server_names(params: dict[str, list[str]]) -> list[str] | None:
    if "servers" not in params:
        return None
    values = [
        item.strip()
        for value in params["servers"]
        for item in value.split(",")
        if item.strip()
    ]
    if not values:
        raise ValueError("'servers' must contain at least one MeowConnect server name")
    return list(dict.fromkeys(values))


def connection_names(connection: dict) -> set[str]:
    return {
        normalize_server_name(value)
        for value in (connection.get("name"), connection.get("shortname"))
        if isinstance(value, str) and value.strip()
    }


def outbound_tag(connection: dict) -> str:
    gate_id = connection["id"]
    for key in ("name", "shortname"):
        value = connection.get(key)
        if isinstance(value, str) and value.strip():
            return f"{value.strip()} [{gate_id}]"
    return str(gate_id)


class UnusableGate(ValueError):
    """One gate cannot yield a dialable outbound; the rest of the pool still can."""


def is_publicly_routable(address: str) -> bool:
    try:
        ip = ipaddress.ip_address(address)
    except ValueError:
        return True
    return not (
        ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_unspecified
    )


def address_sort_key(address: str) -> tuple[int, object]:
    ip = ipaddress.ip_address(address)
    return (ip.version, ip)


def gateway_addresses(connection: dict) -> list[str]:
    gateways = connection.get("gateways")
    if not isinstance(gateways, list):
        return []
    addresses = {
        gateway["address"].strip()
        for gateway in gateways
        if isinstance(gateway, dict)
        and isinstance(gateway.get("address"), str)
        and gateway["address"].strip()
        and is_publicly_routable(gateway["address"].strip())
    }

    return sorted(addresses, key=address_sort_key)


def extract_proxy_outbound(response: object, connection: dict, tag: str) -> dict:
    gate_id = connection["id"]
    if not isinstance(response, dict):
        raise UnusableGate(
            f"cached connect response for server {gate_id} is not an object"
        )
    configuration = response.get("configuration")
    if not isinstance(configuration, dict):
        raise UnusableGate(
            f"cached connect response for server {gate_id} has no configuration"
        )
    outbounds = configuration.get("outbounds")
    if not isinstance(outbounds, list):
        raise UnusableGate(f"server {gate_id} configuration has no outbounds list")
    for raw_outbound in outbounds:
        if not isinstance(raw_outbound, dict):
            continue
        if raw_outbound.get("type") in SKIP_OUTBOUND_TYPES:
            continue
        outbound = deep_clone(raw_outbound)
        outbound["tag"] = tag
        server = outbound.get("server")
        if isinstance(server, str) and not is_publicly_routable(server):
            candidates = gateway_addresses(connection)
            if not candidates:
                raise UnusableGate(
                    f"server {gate_id} advertises unroutable address {server} "
                    "and lists no public gateway to use instead"
                )
            outbound["server"] = candidates[0]
        return outbound
    raise UnusableGate(f"server {gate_id} configuration has no proxy outbound")


def build_meowconnect_outbounds(
    raw: dict, server_names: list[str] | None, routing: str
) -> list[dict]:
    connections = raw.get("connections")
    responses = raw.get("responses")
    if not isinstance(connections, list) or not isinstance(responses, dict):
        raise ValueError("raw MeowConnect cache is malformed")

    requested = (
        {normalize_server_name(name) for name in server_names}
        if server_names is not None
        else None
    )
    matched: set[str] = set()
    available_names: list[str] = []
    selected: list[tuple[dict, str, object]] = []

    for connection in connections:
        if not isinstance(connection, dict) or not isinstance(
            connection.get("id"), int
        ):
            continue
        gate_id = connection["id"]
        names = connection_names(connection)
        display_name = connection.get("name")
        if isinstance(display_name, str) and display_name:
            available_names.append(display_name)

        if requested is not None:
            matches = requested & names
            should_select = bool(matches)
            matched.update(matches)
        elif routing == "ru-only":
            should_select = RUSSIAN_SERVER_NAME in names
        else:
            should_select = RUSSIAN_SERVER_NAME not in names

        if should_select and str(gate_id) in responses:
            selected.append(
                (connection, outbound_tag(connection), responses[str(gate_id)])
            )

    if requested is not None:
        missing = requested - matched
        if missing:
            raise ValueError(
                "Unknown MeowConnect server name(s): "
                + ", ".join(sorted(missing))
                + ". Available: "
                + ", ".join(available_names)
            )

    outbounds = []
    skipped: list[str] = []
    for connection, tag, response in selected:
        try:
            outbounds.append(extract_proxy_outbound(response, connection, tag))
        except UnusableGate as exc:
            skipped.append(f"{tag} ({exc})")
    if skipped:
        print("Skipped unusable MeowConnect gates: " + "; ".join(skipped))
    if not outbounds:
        raise ValueError(
            "No usable MeowConnect gates; skipped " + "; ".join(skipped)
            if skipped
            else "Selected MeowConnect servers have no cached responses"
        )
    return outbounds


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


def build_proxy_outbounds(provided_outbounds: list[dict]):
    proxy_outbounds = []
    tags = []
    for raw_outbound in provided_outbounds:
        if not isinstance(raw_outbound, dict):
            raise ValueError("Each cached outbound must be a JSON object")

        outbound = deep_clone(raw_outbound)
        tag = outbound.get("tag")
        if not isinstance(tag, str) or not tag.strip():
            raise ValueError("Each cached outbound must have a string tag")

        tags.append(tag)
        proxy_outbounds.append(outbound)

    if len(proxy_outbounds) == 1:
        return proxy_outbounds

    generated = proxy_outbounds + [build_urltest(AUTOMATIC_OUTBOUND_TAG, tags)]
    generated.append(
        {
            "type": "selector",
            "tag": "proxy",
            "outbounds": [AUTOMATIC_OUTBOUND_TAG] + tags,
            "default": AUTOMATIC_OUTBOUND_TAG,
        }
    )
    return generated


def set_generated_outbounds(config, generated_outbounds):
    outbounds = config.get("outbounds")
    if not isinstance(outbounds, list):
        outbounds = []

    base_outbounds = []
    for outbound in outbounds:
        if not isinstance(outbound, dict):
            continue
        if outbound.get("tag") in {"proxy", AUTOMATIC_OUTBOUND_TAG}:
            continue
        base_outbounds.append(outbound)

    config["outbounds"] = base_outbounds + generated_outbounds


AD_RULE_SETS = frozenset(
    {
        "geosite-category-ads-all",
        "geosite-adguard-list",
        "category-ads-all",
    }
)


def remove_rule_sets(rules, targets: frozenset[str]):
    if not isinstance(rules, list):
        return rules

    filtered = []
    for rule in rules:
        if not isinstance(rule, dict):
            filtered.append(rule)
            continue
        rule_sets = rule.get("rule_set")
        if isinstance(rule_sets, list):
            kept = [item for item in rule_sets if item not in targets]
            if not kept and rule_sets:
                continue
            if kept != rule_sets:
                rule = dict(rule)
                rule["rule_set"] = kept
        elif isinstance(rule_sets, str) and rule_sets in targets:
            continue
        filtered.append(rule)
    return filtered


def allow_ads(config):
    for section_name in ("dns", "route"):
        section = config.get(section_name)
        if isinstance(section, dict) and isinstance(section.get("rules"), list):
            section["rules"] = remove_rule_sets(section["rules"], AD_RULE_SETS)
    route = config.get("route")
    if isinstance(route, dict) and isinstance(route.get("rule_set"), list):
        route["rule_set"] = [
            definition
            for definition in route["rule_set"]
            if not (
                isinstance(definition, dict) and definition.get("tag") in AD_RULE_SETS
            )
        ]


PROXY_REFERENCE_KEYS = frozenset({"outbound", "detour", "final"})


def replace_proxy_references(value, outbound_tag: str):
    if isinstance(value, dict):
        return {
            key: (
                outbound_tag
                if key in PROXY_REFERENCE_KEYS and item == "proxy"
                else replace_proxy_references(item, outbound_tag)
            )
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [replace_proxy_references(item, outbound_tag) for item in value]
    return value


def remove_redundant_final_route_rules(config, route_final: str):
    route = config.get("route")
    if not isinstance(route, dict):
        return
    rules = route.get("rules")
    if not isinstance(rules, list):
        return

    route["rules"] = [
        rule
        for rule in rules
        if not (isinstance(rule, dict) and rule.get("outbound") == route_final)
    ]


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


RUSSIAN_RULE_SETS = frozenset(
    {
        "geosite-ru-available-only-inside",
        "geosite-ru-blocked",
        "geoip-ru",
        "geoip-ru-blocked",
        "geoip-ru-blocked-community",
        "geoip-re-filter",
    }
)
RUSSIAN_DOMAIN_RULE_SETS = (
    "geosite-ru-available-only-inside",
    "geosite-ru-blocked",
)


def rule_set_values(rule: dict) -> set[str]:
    value = rule.get("rule_set")
    if isinstance(value, str):
        return {value}
    if isinstance(value, list):
        return {item for item in value if isinstance(item, str)}
    return set()


def set_rule_set_detour(config, detour: str):
    for client in config.get("http_clients", []):
        if isinstance(client, dict):
            client["detour"] = detour


def configure_ru_only(config):
    route = config.get("route")
    if isinstance(route, dict):
        rules = route.get("rules")
        if isinstance(rules, list):
            for rule in rules:
                if not isinstance(rule, dict):
                    continue
                if rule_set_values(rule) & RUSSIAN_RULE_SETS or (
                    "domain_suffix" in rule and rule.get("outbound") == "direct"
                ):
                    rule["outbound"] = "proxy"

    set_rule_set_detour(config, "direct")

    dns = config.get("dns")
    if not isinstance(dns, dict):
        return
    dns["final"] = "local-dns"
    rules = dns.get("rules")
    if not isinstance(rules, list):
        return
    rules.extend(
        [
            {
                "rule_set": list(RUSSIAN_DOMAIN_RULE_SETS),
                "server": "remote-doh-1",
            },
            {
                "domain_suffix": list(RU_DOMAIN_SUFFIXES),
                "server": "remote-doh-1",
            },
        ]
    )


def remove_ru_direct_rules(config):
    route = config.get("route")
    if not isinstance(route, dict):
        return
    rules = route.get("rules")
    if isinstance(rules, list):
        rules = remove_rule_sets(rules, RU_DIRECT_RULE_SETS)
        route["rules"] = [
            rule
            for rule in rules
            if not (
                isinstance(rule, dict)
                and rule.get("outbound") == "direct"
                and rule.get("domain_suffix")
                and set(rule["domain_suffix"]) <= set(RU_DOMAIN_SUFFIXES)
            )
        ]
    if isinstance(route.get("rule_set"), list):
        route["rule_set"] = [
            definition
            for definition in route["rule_set"]
            if not (
                isinstance(definition, dict)
                and definition.get("tag") in RU_DIRECT_RULE_SETS
            )
        ]


def set_direct_dns(config):
    dns = config.get("dns")
    if isinstance(dns, dict):
        dns["final"] = "local-dns"
    route = config.get("route")
    if isinstance(route, dict) and "default_domain_resolver" in route:
        route["default_domain_resolver"] = "local-dns"


def collect_rule_set_references(value, seen: set[str]):
    if isinstance(value, dict):
        rule_sets = value.get("rule_set")
        if isinstance(rule_sets, str):
            seen.add(rule_sets)
        elif isinstance(rule_sets, list):
            seen.update(item for item in rule_sets if isinstance(item, str))
        for item in value.values():
            collect_rule_set_references(item, seen)
    elif isinstance(value, list):
        for item in value:
            collect_rule_set_references(item, seen)


def prune_unused_rule_sets(config):
    route = config.get("route")
    if not isinstance(route, dict) or not isinstance(route.get("rule_set"), list):
        return

    referenced: set[str] = set()
    collect_rule_set_references(route.get("rules"), referenced)
    dns = config.get("dns")
    if isinstance(dns, dict):
        collect_rule_set_references(dns.get("rules"), referenced)

    route["rule_set"] = [
        definition
        for definition in route["rule_set"]
        if not isinstance(definition, dict) or definition.get("tag") in referenced
    ]


def configure_routing(config, routing: str):
    if routing in {"all-except-ru", "all-including-ru"}:
        set_route_final(config, "proxy")
        remove_redundant_final_route_rules(config, "proxy")
    else:
        set_route_final(config, "direct")
    if routing == "all-including-ru":
        remove_ru_direct_rules(config)
    if routing == "ru-only":
        configure_ru_only(config)
    if routing == "blocked":
        set_direct_dns(config)


def set_inbounds(config, mode: str):
    inbounds = config.get("inbounds")
    if not isinstance(inbounds, list):
        return

    target_mode = mode.lower()
    if target_mode == "proxy":
        allowed_types = {"socks", "http"}
    else:
        allowed_types = {"tun"}

    config["inbounds"] = [
        dict(inbound)
        for inbound in inbounds
        if isinstance(inbound, dict) and inbound.get("type") in allowed_types
    ]
    trim_route_rules_for_inbounds(
        config,
        {
            inbound["tag"]
            for inbound in config["inbounds"]
            if isinstance(inbound.get("tag"), str) and inbound["tag"]
        },
    )


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


class GeneratorService:
    def __init__(self, state_dir: Path) -> None:
        self.cache = RawResponseCache(state_dir)
        self.lock = threading.Lock()

    def refresh(self) -> dict:
        with self.lock:
            client = MeowConnectClient(load_client_config())
            raw, meta = fetch_raw_responses(client)
            if self.cache.exists():
                merge_previous_responses(raw, self.cache.load_raw(), meta)
            self.cache.save(raw, meta)
            return meta

    def load_raw(self) -> dict:
        with self.lock:
            if not self.cache.exists():
                raise FileNotFoundError("MeowConnect raw response cache is empty")
            return self.cache.load_raw()


def merge_previous_responses(raw: dict, previous: dict, meta: dict) -> None:
    connections = raw.get("connections")
    responses = raw.get("responses")
    previous_responses = previous.get("responses")
    if (
        not isinstance(connections, list)
        or not isinstance(responses, dict)
        or not isinstance(previous_responses, dict)
    ):
        return

    current_ids = {
        str(connection["id"])
        for connection in connections
        if isinstance(connection, dict) and isinstance(connection.get("id"), int)
    }
    stale_ids = []
    for gate_id in current_ids:
        if gate_id not in responses and gate_id in previous_responses:
            responses[gate_id] = previous_responses[gate_id]
            stale_ids.append(int(gate_id))
    meta["stale_response_ids"] = sorted(stale_ids)
    meta["response_count"] = len(responses)


def params_from_mapping(raw: object) -> dict[str, list[str]]:
    if not isinstance(raw, dict):
        raise ValueError("shortcut parameters must be a JSON object")
    params: dict[str, list[str]] = {}
    for key, value in raw.items():
        if not isinstance(key, str):
            raise ValueError("shortcut parameter names must be strings")
        if isinstance(value, bool):
            params[key] = ["true" if value else "false"]
        elif isinstance(value, (str, int)):
            params[key] = [str(value)]
        elif isinstance(value, list) and all(
            isinstance(item, (str, int)) for item in value
        ):
            params[key] = [str(item) for item in value]
        else:
            raise ValueError(f"unsupported shortcut value for '{key}'")
    return params


class Handler(BaseHTTPRequestHandler):
    route_path = "/"
    refresh_path = "/sing-box-refresh/"
    template: object = None
    shortcuts: dict[str, object] = {}
    service: GeneratorService | None = None

    def do_GET(self):
        parsed = urlparse(self.path)
        try:
            params = self.resolve_params(parsed)
        except FileNotFoundError:
            self.send_error(404, "Not Found")
            return
        except ValueError as exc:
            self.send_error(400, None, str(exc))
            return

        cfg = deep_clone(self.template)
        try:
            routing_raw = first(params, "routing", "blocked")
            routing = (routing_raw or "blocked").strip().lower()
            if routing not in ROUTING_MODES:
                raise ValueError(
                    "Bad routing value; use all-except-ru, all-including-ru, "
                    "blocked, or ru-only"
                )
            server_names = parse_server_names(params)
            raw = self._service().load_raw()
            proxy_outbounds = build_meowconnect_outbounds(
                raw,
                server_names,
                routing,
            )
            generated_outbounds = build_proxy_outbounds(proxy_outbounds)
            set_generated_outbounds(cfg, generated_outbounds)
            configure_routing(cfg, routing)
            proxy_tag = "proxy"
            if len(proxy_outbounds) == 1:
                proxy_tag = proxy_outbounds[0]["tag"]
                cfg = replace_proxy_references(cfg, proxy_tag)
            reorder_outbounds(
                cfg,
                proxy_tag
                if routing in {"all-except-ru", "all-including-ru"}
                else "direct",
            )
        except ValueError as exc:
            self.send_error(400, None, str(exc))
            return
        except FileNotFoundError as exc:
            self.send_error(503, None, str(exc))
            return

        inbound_raw = first(params, "inbound", "tun")
        inbound_mode = (inbound_raw or "tun").strip().lower()
        if inbound_mode not in {"tun", "proxy"}:
            self.send_error(400, "Bad inbound value; use tun or proxy")
            return
        set_inbounds(cfg, inbound_mode)

        if is_truthy(first(params, "proxy_public", None)):
            set_proxy_inbounds_listen(cfg, "0.0.0.0")

        if is_truthy(first(params, "allow_ads", None)):
            allow_ads(cfg)

        prune_unused_rule_sets(cfg)

        body = json.dumps(cfg, indent=4, ensure_ascii=False).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != self.refresh_path:
            self.send_error(404, "Not Found")
            return
        if self.client_address[0] not in {"127.0.0.1", "::1"}:
            self.send_error(403, "Refresh is local-only")
            return
        try:
            meta = self._service().refresh()
        except Exception as exc:
            self.send_error(500, None, str(exc))
            return
        self._json_response(200, meta)

    def resolve_params(self, parsed):
        request_params = parse_qs(parsed.query, keep_blank_values=True)
        if parsed.path == self.route_path:
            return request_params

        shortcut_params = self.load_shortcut_params(parsed.path)
        shortcut_params.update(request_params)
        return shortcut_params

    def load_shortcut_params(self, request_path: str):
        route_prefix = self.route_path.rsplit("/", 1)[0]
        if not request_path.startswith(route_prefix + "/"):
            raise FileNotFoundError

        relative = unquote(request_path[len(route_prefix) + 1 :])
        if not relative or "/" in relative or "\x00" in relative:
            raise FileNotFoundError
        if relative not in self.shortcuts:
            raise FileNotFoundError
        return params_from_mapping(self.shortcuts[relative])

    def _service(self) -> GeneratorService:
        if self.service is None:
            raise RuntimeError("generator service is not configured")
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


def load_json(path: str):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        raise SystemExit(f"Failed to parse JSON {path}: {e}")


def main():
    ap = argparse.ArgumentParser(description="sing-box config templating HTTP server")
    ap.add_argument("--file", required=True, help="Path to base sing-box config (JSON)")
    ap.add_argument(
        "--shortcuts-file",
        required=True,
        help="Path to the JSON shortcut manifest",
    )
    ap.add_argument(
        "--state-dir",
        default="/var/lib/meowconnect",
        help="Directory for raw MeowConnect responses",
    )
    ap.add_argument("--path", default="/", help="URL path to serve (default: /)")
    ap.add_argument(
        "--host", default="127.0.0.1", help="Bind host (default: 127.0.0.1)"
    )
    ap.add_argument("--port", type=int, default=8080, help="Bind port (default: 8080)")
    args = ap.parse_args()

    Handler.route_path = args.path
    Handler.template = load_json(args.file)
    shortcuts = load_json(args.shortcuts_file)
    if not isinstance(shortcuts, dict):
        raise SystemExit("Shortcut manifest must be a JSON object")
    Handler.shortcuts = shortcuts

    service = GeneratorService(Path(args.state_dir))
    if not service.cache.exists():
        print("Raw MeowConnect cache missing; running initial refresh...")
        meta = service.refresh()
        print(
            f"Initial refresh complete: {meta.get('response_count', 0)} responses "
            f"in {meta.get('duration_seconds', '?')}s"
        )
    Handler.service = service

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
