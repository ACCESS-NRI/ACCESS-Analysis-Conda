#!/usr/bin/env python3
"""Check pixi lockfiles for packages resolved from broken-labelled channels."""

from __future__ import annotations

import argparse
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable
from urllib.parse import urlparse

BROKEN_URL_RE = re.compile(r"https://[^\s\"']+/label/broken/[^\s\"']+")


@dataclass(frozen=True, order=True)
class BrokenPackage:
    """A resolved package sourced from a broken-labelled channel."""

    name: str
    version: str
    build: str
    url: str


@dataclass(frozen=True)
class BrokenPackageReport:
    """Comparison summary for broken-labelled packages between two lockfiles."""

    current: tuple[BrokenPackage, ...]
    added: tuple[BrokenPackage, ...]
    removed: tuple[BrokenPackage, ...]
    disallowed: tuple[BrokenPackage, ...]
    allowlist: frozenset[str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check pixi lockfiles for packages resolved from /label/broken/ URLs."
    )
    parser.add_argument("--base-lockfile", type=Path, required=True)
    parser.add_argument("--head-lockfile", type=Path, required=True)
    parser.add_argument("--allowlist-file", type=Path, required=True)
    parser.add_argument("--markdown-output", type=Path, required=True)
    parser.add_argument(
        "--github-output",
        type=Path,
        default=None,
        help="Optional GitHub Actions output file path.",
    )
    return parser.parse_args()


def read_allowlist(path: Path) -> frozenset[str]:
    entries: set[str] = set()
    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        entries.add(line)
    return frozenset(entries)


def parse_broken_packages(lockfile: Path) -> tuple[BrokenPackage, ...]:
    text = lockfile.read_text()
    packages: set[BrokenPackage] = set()

    for url in BROKEN_URL_RE.findall(text):
        filename = Path(urlparse(url).path).name
        stem = filename.removesuffix(".conda").removesuffix(".tar.bz2")
        name, version, build = stem.rsplit("-", 2)
        packages.add(BrokenPackage(name=name, version=version, build=build, url=url))

    return tuple(sorted(packages))


def build_report(
    base_lockfile: Path, head_lockfile: Path, allowlist_file: Path
) -> BrokenPackageReport:
    allowlist = read_allowlist(allowlist_file)
    base = parse_broken_packages(base_lockfile)
    head = parse_broken_packages(head_lockfile)

    base_set = set(base)
    head_set = set(head)

    added = tuple(sorted(head_set - base_set))
    removed = tuple(sorted(base_set - head_set))
    disallowed = tuple(pkg for pkg in head if pkg.name not in allowlist)

    return BrokenPackageReport(
        current=head,
        added=added,
        removed=removed,
        disallowed=disallowed,
        allowlist=allowlist,
    )


def render_package_list(packages: Iterable[BrokenPackage]) -> list[str]:
    items = list(packages)
    if not items:
        return ["- none"]

    lines: list[str] = []
    for package in items:
        lines.append(f"- `{package.name}` {package.version} `{package.build}`")
        lines.append(f"  - `{package.url}`")
    return lines


def render_markdown(report: BrokenPackageReport) -> str:
    allowlist_display = ", ".join(sorted(report.allowlist)) if report.allowlist else "(empty)"
    lines: list[str] = [
        "## Pixi broken package check",
        "",
        f"Allowlist: `{allowlist_display}`",
        "",
        f"Current broken-label packages in `pixi.lock`: **{len(report.current)}**",
        *render_package_list(report.current),
        "",
        f"Added vs base branch: **{len(report.added)}**",
        *render_package_list(report.added),
        "",
        f"Removed vs base branch: **{len(report.removed)}**",
        *render_package_list(report.removed),
        "",
    ]

    if report.disallowed:
        lines.extend([
            "❌ Disallowed broken-label packages detected:",
            "",
            *render_package_list(report.disallowed),
        ])
    else:
        lines.append("✅ All broken-label packages are allowlisted.")

    return "\n".join(lines) + "\n"


def write_github_output(path: Path | None, has_violations: bool) -> None:
    output_path = path or Path(os.environ.get("GITHUB_OUTPUT", ""))
    if not str(output_path):
        return
    with output_path.open("a") as handle:
        handle.write(f"violations={'true' if has_violations else 'false'}\n")


def main() -> int:
    args = parse_args()
    report = build_report(
        base_lockfile=args.base_lockfile,
        head_lockfile=args.head_lockfile,
        allowlist_file=args.allowlist_file,
    )
    args.markdown_output.write_text(render_markdown(report))
    write_github_output(args.github_output, has_violations=bool(report.disallowed))
    return 1 if report.disallowed else 0


if __name__ == "__main__":
    raise SystemExit(main())
