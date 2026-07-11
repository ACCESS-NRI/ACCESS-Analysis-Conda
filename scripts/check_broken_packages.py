#!/usr/bin/env python3
"""Check that broken-labelled packages in a pixi lock match pixi.toml declarations."""

from __future__ import annotations

import argparse
import os
import re
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urlparse

BROKEN_URL_RE = re.compile(r"https://[^\s\"']+/label/broken/[^\s\"']+")
BROKEN_CHANNEL_MARKER = "/label/broken"


@dataclass(frozen=True, order=True)
class BrokenPackage:
    """A resolved package sourced from a broken-labelled channel."""

    name: str
    version: str
    build: str
    url: str


@dataclass(frozen=True)
class BrokenPackageReport:
    """Summary comparing broken-labelled lock entries with pixi.toml declarations."""

    declared: frozenset[str]
    resolved: tuple[BrokenPackage, ...]
    unexpected: tuple[BrokenPackage, ...]
    missing: tuple[str, ...]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Check that packages resolved from /label/broken/ in pixi.lock are "
            "exactly the packages explicitly configured to use broken channels in pixi.toml."
        )
    )
    parser.add_argument("--pixi-toml", type=Path, required=True)
    parser.add_argument("--lockfile", type=Path, required=True)
    parser.add_argument("--markdown-output", type=Path, required=True)
    parser.add_argument(
        "--github-output",
        type=Path,
        default=None,
        help="Optional GitHub Actions output file path.",
    )
    return parser.parse_args()


def dependency_uses_broken_channel(spec: Any) -> bool:
    return isinstance(spec, dict) and isinstance(spec.get("channel"), str) and BROKEN_CHANNEL_MARKER in spec["channel"]


def declared_broken_packages(pixi_toml: Path) -> frozenset[str]:
    data = tomllib.loads(pixi_toml.read_text())
    declared: set[str] = set()

    def scan_table(table: Any) -> None:
        if not isinstance(table, dict):
            return
        for name, spec in table.items():
            if dependency_uses_broken_channel(spec):
                declared.add(name)

    scan_table(data.get("dependencies"))

    feature_table = data.get("feature")
    if isinstance(feature_table, dict):
        for feature in feature_table.values():
            if isinstance(feature, dict):
                scan_table(feature.get("dependencies"))
                target_table = feature.get("target")
                if isinstance(target_table, dict):
                    for target in target_table.values():
                        if isinstance(target, dict):
                            scan_table(target.get("dependencies"))

    target_table = data.get("target")
    if isinstance(target_table, dict):
        for target in target_table.values():
            if isinstance(target, dict):
                scan_table(target.get("dependencies"))

    return frozenset(declared)


def resolved_broken_packages(lockfile: Path) -> tuple[BrokenPackage, ...]:
    text = lockfile.read_text()
    packages: set[BrokenPackage] = set()

    for url in BROKEN_URL_RE.findall(text):
        filename = Path(urlparse(url).path).name
        stem = filename.removesuffix('.conda').removesuffix('.tar.bz2')
        name, version, build = stem.rsplit('-', 2)
        packages.add(BrokenPackage(name=name, version=version, build=build, url=url))

    return tuple(sorted(packages))


def build_report(pixi_toml: Path, lockfile: Path) -> BrokenPackageReport:
    declared = declared_broken_packages(pixi_toml)
    resolved = resolved_broken_packages(lockfile)
    resolved_names = {package.name for package in resolved}
    unexpected = tuple(package for package in resolved if package.name not in declared)
    missing = tuple(sorted(declared - resolved_names))
    return BrokenPackageReport(
        declared=declared,
        resolved=resolved,
        unexpected=unexpected,
        missing=missing,
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


def render_name_list(names: Iterable[str]) -> list[str]:
    items = list(names)
    if not items:
        return ["- none"]
    return [f"- `{name}`" for name in items]


def render_markdown(report: BrokenPackageReport) -> str:
    declared_display = ", ".join(sorted(report.declared)) if report.declared else "(none)"
    lines: list[str] = [
        "## Pixi broken package check",
        "",
        f"Packages explicitly configured with broken-labelled channels in `pixi.toml`: `{declared_display}`",
        "",
        f"Packages actually resolved from broken-labelled channels in `pixi.lock`: **{len(report.resolved)}**",
        *render_package_list(report.resolved),
        "",
        "Unexpected broken-label packages (in lock, not declared in `pixi.toml`):",
        *render_package_list(report.unexpected),
        "",
        "Declared broken-label packages missing from the lock:",
        *render_name_list(report.missing),
        "",
    ]
    if report.unexpected or report.missing:
        lines.append("❌ Broken-label packages in `pixi.lock` do not match `pixi.toml` declarations.")
    else:
        lines.append("✅ Broken-label packages in `pixi.lock` exactly match `pixi.toml` declarations.")
    return "\n".join(lines) + "\n"


def write_github_output(path: Path | None, has_violations: bool) -> None:
    output_path = path or Path(os.environ.get("GITHUB_OUTPUT", ""))
    if not str(output_path):
        return
    with output_path.open("a") as handle:
        handle.write(f"violations={'true' if has_violations else 'false'}\n")


def main() -> int:
    args = parse_args()
    report = build_report(args.pixi_toml, args.lockfile)
    args.markdown_output.write_text(render_markdown(report))
    has_violations = bool(report.unexpected or report.missing)
    write_github_output(args.github_output, has_violations)
    return 1 if has_violations else 0


if __name__ == "__main__":
    raise SystemExit(main())
