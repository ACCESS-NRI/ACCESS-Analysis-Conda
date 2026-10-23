#!/usr/bin/env python3
"""Advance analysis3's version and aliases for the next monthly release."""

import argparse
from datetime import date, datetime
import os
from pathlib import Path
import re
from zoneinfo import ZoneInfo


CONFIG = Path(__file__).resolve().parents[1] / "environments/analysis3/config.sh"
VERSION_RE = re.compile(r"^(export (?:VERSION_TO_MODIFY|STABLE_VERSION|UNSTABLE_VERSION)=)(\d{2}\.\d{2})$", re.MULTILINE)


def version_for(year: int, month: int) -> str:
    return f"{year % 100:02d}.{month:02d}"


def next_version(version: str) -> str:
    year, month = map(int, version.split("."))
    if not 1 <= month <= 12:
        raise ValueError(f"Invalid analysis3 version: {version}")
    return version_for(2000 + year + (month == 12), month % 12 + 1)


def prepare(config: Path, target: str) -> bool:
    if not re.fullmatch(r"\d{2}\.(0[1-9]|1[0-2])", target):
        raise ValueError(f"Invalid target version: {target}; expected YY.MM")

    original = config.read_text()
    values = dict(re.findall(r"^export (VERSION_TO_MODIFY|STABLE_VERSION|UNSTABLE_VERSION)=(\d{2}\.\d{2})$", original, re.MULTILINE))
    if len(values) != 3:
        raise ValueError(f"Expected exactly three analysis3 version settings in {config}")
    current = values["VERSION_TO_MODIFY"]
    if values["UNSTABLE_VERSION"] != current:
        raise ValueError("UNSTABLE_VERSION must match VERSION_TO_MODIFY")
    if next_version(values["STABLE_VERSION"]) != current:
        raise ValueError("STABLE_VERSION must be the previous monthly version")
    if target == current:
        return False
    if next_version(current) != target:
        raise ValueError(f"Refusing to skip or rewind from {current} to {target}")

    replacements = {
        "VERSION_TO_MODIFY": target,
        "STABLE_VERSION": current,
        "UNSTABLE_VERSION": target,
    }
    counts = {key: 0 for key in replacements}

    def replace(match: re.Match[str]) -> str:
        prefix = match.group(1)
        key = prefix.removeprefix("export ").removesuffix("=")
        counts[key] += 1
        return prefix + replacements[key]

    updated = VERSION_RE.sub(replace, original)
    if any(count != 1 for count in counts.values()):
        raise ValueError(f"Expected one assignment for each version setting: {counts}")
    config.write_text(updated)
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-version", help="Override next month's YY.MM version for a manual run")
    parser.add_argument("--date", help="Date in Australia/Brisbane (YYYY-MM-DD), for reproducible runs")
    args = parser.parse_args()

    today = date.fromisoformat(args.date) if args.date else datetime.now(ZoneInfo("Australia/Brisbane")).date()
    next_month = 1 if today.month == 12 else today.month + 1
    next_year = today.year + (today.month == 12)
    target = args.target_version or version_for(next_year, next_month)
    changed = prepare(CONFIG, target)
    print(f"analysis3-{target}: {'prepared' if changed else 'already configured'}")

    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as handle:
            handle.write(f"version={target}\nchanged={str(changed).lower()}\n")


if __name__ == "__main__":
    main()
