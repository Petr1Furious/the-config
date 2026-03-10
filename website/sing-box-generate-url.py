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
    "allow_ads": False,
    "no_ru_blocked_community": False,
    "no_re_filter": False,
    "vless": [
        {
            "tag": "vless-s1",
            "server": "example-vless-1.com",
            "server_port": 443,
            "uuid": "00000000-0000-0000-0000-000000000000",
            "flow": "",
            "server_name": "cdn.example.com",
            "fingerprint": "chrome",
            "public_key": "REALITY_PUBLIC_KEY",
            "short_id": "abcd1234",
        }
    ],
    "hy2": [
        {
            "tag": "hy2-s1",
            "server": "example-hy2-1.com",
            "server_port": 443,
            "up_mbps": 100,
            "down_mbps": 100,
            "password": "hy2-password",
            "obfs_type": "salamander",
            "obfs_password": "obfs-password",
            "server_name": "cdn.example.com",
            "fingerprint": "chrome",
        }
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

    vless = spec.get("vless", [])
    hy2 = spec.get("hy2", [])

    if not isinstance(vless, (dict, list)):
        raise ValueError("'vless' must be an object or array")
    if not isinstance(hy2, (dict, list)):
        raise ValueError("'hy2' must be an object or array")

    if not vless and not hy2:
        raise ValueError("At least one of 'vless' or 'hy2' must be provided")

    params["vless"] = compact_json(vless)
    params["hy2"] = compact_json(hy2)
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
