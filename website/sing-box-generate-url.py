#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
from urllib.parse import urlencode


DEFAULT_BASE_URL = "https://petr1furious.me/sing-box/generate"


EXAMPLE_SPEC = {
    "base_url": DEFAULT_BASE_URL,
    "primary": "proxy",
    "inbound": "tun",
    "legacy": False,
    "allow_ads": False,
    "no_ru_blocked_community": False,
    "no_re_filter": False,
    "outbounds": [
        {
            "type": "vless",
            "tag": "proxy-s1",
            "server": "example-vless-1.com",
            "server_port": 443,
            "uuid": "00000000-0000-0000-0000-000000000000",
            "tls": {
                "enabled": True,
                "server_name": "cdn.example.com",
                "utls": {
                    "enabled": True,
                    "fingerprint": "chrome",
                },
                "reality": {
                    "enabled": True,
                    "public_key": "REALITY_PUBLIC_KEY",
                    "short_id": "abcd1234",
                },
            },
        },
        {
            "type": "hysteria2",
            "tag": "proxy-s2",
            "server": "example-hy2-1.com",
            "server_port": 443,
            "password": "hy2-password",
            "obfs": {
                "type": "salamander",
                "password": "obfs-password",
            },
            "tls": {
                "enabled": True,
                "server_name": "cdn.example.com",
            },
        },
    ],
}


def compact_json(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def load_spec(path: Path):
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("Spec root must be a JSON object")
    return data


def build_query(spec: dict):
    params = {}

    for key in (
        "primary",
        "inbound",
        "legacy",
        "fixed_outbound",
        "proxy_public",
        "allow_ads",
        "no_ru_blocked_community",
        "no_re_filter",
    ):
        if key in spec:
            value = spec[key]
            if isinstance(value, bool):
                params[key] = "true" if value else "false"
            elif value is not None:
                params[key] = str(value)

    outbounds = spec.get("outbounds", [])
    if not isinstance(outbounds, (dict, list)):
        raise ValueError("'outbounds' must be an object or array")
    if not outbounds:
        raise ValueError("'outbounds' must contain at least one outbound")

    params["outbounds"] = compact_json(outbounds)
    return params


def main():
    ap = argparse.ArgumentParser(
        description="Build encoded /sing-box/generate URL from JSON spec"
    )
    ap.add_argument(
        "--spec",
        type=Path,
        help="Path to spec JSON file (see --print-example)",
    )
    ap.add_argument(
        "--base-url",
        default=None,
        help="Override base URL (otherwise spec.base_url or default is used)",
    )
    ap.add_argument(
        "--print-example",
        action="store_true",
        help="Print an example spec JSON and exit",
    )
    ap.add_argument(
        "--curl",
        action="store_true",
        help="Print curl command instead of plain URL",
    )
    args = ap.parse_args()

    if args.print_example:
        print(json.dumps(EXAMPLE_SPEC, indent=2, ensure_ascii=False))
        return

    if args.spec is None:
        raise SystemExit("Missing required --spec (or use --print-example)")

    spec = load_spec(args.spec)
    base_url = args.base_url or spec.get("base_url") or DEFAULT_BASE_URL
    query = build_query(spec)
    url = f"{base_url}?{urlencode(query)}"

    if args.curl:
        print(f"curl -fsSL '{url}'")
    else:
        print(url)


if __name__ == "__main__":
    main()
