#!/usr/bin/env python3
"""Inventory literal remote_ip entries in Caddy configuration files."""

from __future__ import annotations

import argparse
import ipaddress
import json
import shlex
import sys
from dataclasses import asdict, dataclass
from pathlib import Path


CANDIDATE_NAMES = {"Caddyfile"}
CANDIDATE_SUFFIXES = {".caddy", ".caddyfile"}
SPECIAL_TOKENS = {"private_ranges"}


@dataclass
class Occurrence:
    path: str
    line: int
    snippet: str | None
    matcher: str | None
    addresses: list[str]
    unparsed: list[str]


def tokenize(line: str) -> list[str]:
    lexer = shlex.shlex(line, posix=True, punctuation_chars="{}")
    lexer.whitespace_split = True
    lexer.commenters = "#"
    return list(lexer)


def classify(values: list[str]) -> tuple[list[str], list[str]]:
    addresses: list[str] = []
    unparsed: list[str] = []
    for value in values:
        if value in SPECIAL_TOKENS:
            addresses.append(value)
            continue
        try:
            ipaddress.ip_network(value, strict=False)
        except ValueError:
            unparsed.append(value)
        else:
            addresses.append(value)
    return addresses, unparsed


def scan_file(path: Path) -> list[Occurrence]:
    results: list[Occurrence] = []
    depth = 0
    snippet: tuple[str, int] | None = None
    matcher_block: tuple[str, int] | None = None

    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        try:
            tokens = tokenize(line)
        except ValueError as exc:
            results.append(
                Occurrence(str(path), line_number, snippet[0] if snippet else None, None, [], [f"tokenize-error:{exc}"])
            )
            continue

        if not tokens:
            continue

        opening_depth = depth
        if len(tokens) >= 2 and tokens[1] == "{" and tokens[0].startswith("(") and tokens[0].endswith(")"):
            snippet = (tokens[0][1:-1], opening_depth)
        if len(tokens) >= 2 and tokens[1] == "{" and tokens[0].startswith("@"):
            matcher_block = (tokens[0][1:], opening_depth)

        if "remote_ip" in tokens:
            index = tokens.index("remote_ip")
            matcher = matcher_block[0] if matcher_block else None
            for token in tokens[:index]:
                if token.startswith("@"):
                    matcher = token[1:]
            raw_values = [token for token in tokens[index + 1 :] if token not in {"{", "}"}]
            addresses, unparsed = classify(raw_values)
            results.append(
                Occurrence(
                    str(path),
                    line_number,
                    snippet[0] if snippet else None,
                    matcher,
                    addresses,
                    unparsed,
                )
            )

        depth += tokens.count("{") - tokens.count("}")
        if matcher_block and depth <= matcher_block[1]:
            matcher_block = None
        if snippet and depth <= snippet[1]:
            snippet = None

    return results


def candidate_files(paths: list[Path]) -> list[Path]:
    files: set[Path] = set()
    for path in paths:
        if path.is_file():
            files.add(path.resolve())
        elif path.is_dir():
            for child in path.rglob("*"):
                if child.is_file() and (child.name in CANDIDATE_NAMES or child.suffix.lower() in CANDIDATE_SUFFIXES):
                    files.add(child.resolve())
        else:
            raise FileNotFoundError(path)
    return sorted(files)


def emit_fragment(results: list[Occurrence], snippet: str, matcher: str) -> int:
    selected = [item for item in results if item.snippet == snippet and item.matcher == matcher]
    if not selected:
        print(f"No remote_ip entries found for snippet={snippet!r}, matcher={matcher!r}.", file=sys.stderr)
        return 1
    unparsed = [token for item in selected for token in item.unparsed]
    if unparsed:
        print("Cannot emit a fragment while unparsed tokens remain: " + ", ".join(unparsed), file=sys.stderr)
        return 2
    values = list(dict.fromkeys(token for item in selected for token in item.addresses))
    print(f"@{matcher} remote_ip {' '.join(values)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=Path, help="Caddy files or directories to scan")
    parser.add_argument("--json", action="store_true", help="emit JSON")
    parser.add_argument("--emit-fragment", action="store_true", help="emit one deduplicated matcher")
    parser.add_argument("--snippet", help="enclosing snippet name for --emit-fragment")
    parser.add_argument("--matcher", help="matcher name without @ for --emit-fragment")
    args = parser.parse_args()

    if args.emit_fragment and (not args.snippet or not args.matcher):
        parser.error("--emit-fragment requires --snippet and --matcher")

    try:
        files = candidate_files(args.paths)
    except FileNotFoundError as exc:
        print(f"Path not found: {exc}", file=sys.stderr)
        return 1

    results = [occurrence for path in files for occurrence in scan_file(path)]
    if args.emit_fragment:
        return emit_fragment(results, args.snippet, args.matcher)
    if args.json:
        json.dump([asdict(item) for item in results], sys.stdout, indent=2)
        print()
        return 0

    if not results:
        print("No remote_ip entries found.")
        return 0
    for item in results:
        group = item.snippet or "-"
        matcher = item.matcher or "-"
        values = " ".join(item.addresses) or "-"
        unparsed = " ".join(item.unparsed) or "-"
        print(f"{item.path}:{item.line}\tsnippet={group}\tmatcher={matcher}\taddresses={values}\tunparsed={unparsed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
