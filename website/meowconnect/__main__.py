"""CLI and module entrypoints for MeowConnect."""

from __future__ import annotations

import argparse
import json
import sys

from .client import MeowConnectClient
from .config import load_client_config
from .fetch import fetch_all_outbounds
from .server import main as server_main


def _add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--indent",
        type=int,
        default=2,
        help="JSON indentation (default: 2, use 0 for compact)",
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="MeowConnect client, fetch helper, and cache server.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="Fetch available connections")
    _add_common_args(list_parser)

    connect_parser = subparsers.add_parser(
        "connect",
        help="Fetch sing-box configuration for a connection gate id",
    )
    connect_parser.add_argument("gate_id", type=int)
    _add_common_args(connect_parser)

    profile_parser = subparsers.add_parser("profile", help="Fetch subscription profile")
    _add_common_args(profile_parser)

    fetch_parser = subparsers.add_parser(
        "fetch-outbounds",
        help="Fetch all proxy outbounds with spaced upstream requests",
    )
    _add_common_args(fetch_parser)

    subparsers.add_parser(
        "serve",
        help="Run the local outbound cache HTTP server",
        add_help=False,
    )

    args, server_argv = parser.parse_known_args(argv)
    if args.command == "serve":
        return server_main(server_argv)

    client = MeowConnectClient(load_client_config())
    indent = args.indent or None

    if args.command == "list":
        result = client.list_connections()
    elif args.command == "connect":
        result = client.connect(args.gate_id)
    elif args.command == "profile":
        result = client.profile()
    else:
        outbounds, meta = fetch_all_outbounds(client)
        result = {"meta": meta, "outbounds": outbounds}

    json.dump(result, sys.stdout, indent=indent, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
