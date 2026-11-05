#!/usr/bin/env python3
"""Check analysis3's generated export or installed prefix using only the stdlib.

Policy sources and the remaining compatibility blockers are documented in
docs/analysis3-emudhra-remediation.md. This is deliberately not a general YAML
reader: export validation accepts the exact pinned specifications emitted by
`pixi workspace export conda-environment` and fails closed for relevant packages.
"""

import argparse
import importlib.metadata
import json
from pathlib import Path
import re
import sys


MINIMUMS = {
    "python": "3.12.16",
    "pip": "26.2.2",
    "conda": "26.9.4",
    "certifi": "2026.10.19",
    "ca-certificates": "2026.10.19",  # conda-forge, not defaults
    "virtualenv": "21.14.12",
    "uv": "0.13.6",
    "sigstore": "4.5.1",
    "pixi": "0.82.1",
}
REQUIRED = {"python", "pip", "certifi", "ca-certificates"}


def version_tuple(value):
    # Prereleases and unrecognised versions must not satisfy a security floor.
    if not re.fullmatch(r"\d+(?:\.\d+)*", value):
        raise ValueError(f"not a final numeric version: {value!r}")
    return tuple(int(part) for part in value.split("."))


def check_versions(versions):
    errors = [f"missing required package: {name}" for name in sorted(REQUIRED - versions.keys())]
    for name, minimum in MINIMUMS.items():
        if name not in versions:
            continue
        try:
            actual = version_tuple(versions[name])
            if actual < version_tuple(minimum):
                errors.append(f"{name} {versions[name]} is below {minimum}")
            if name == "python" and actual[:2] != (3, 12):
                errors.append(f"analysis3 must remain on Python 3.12, found {versions[name]}")
        except ValueError as exc:
            errors.append(f"{name}: {exc}")
    return errors


def export_versions(text):
    versions = {}
    errors = []
    for line in text.splitlines():
        match = re.match(r"^\s*-\s+([\w.-]+)(.*)$", line)
        if not match:
            continue
        name, spec = match.groups()
        name = name.lower().replace("_", "-")
        # Pixi adds an unversioned pip marker before its nested pip section.
        # A separately pinned pip entry is still required by check_versions.
        if name not in MINIMUMS or (name == "pip" and spec in ("", ":")):
            continue
        pinned = re.fullmatch(r"\s*==\s*(\d+(?:\.\d+)*)(?:\s+[\w.]+)?\s*", spec)
        if not pinned:
            errors.append(f"{name}: expected an exact final version in generated export: {line.strip()}")
        elif name in versions:
            errors.append(f"duplicate package in export: {name}")
        else:
            versions[name] = pinned[1]
    return versions, errors


def installed_versions():
    versions = {}
    for record in (Path(sys.prefix) / "conda-meta").glob("*.json"):
        data = json.loads(record.read_text())
        if data["name"] in MINIMUMS:
            versions[data["name"]] = data["version"]
    # The running interpreter and installed distribution metadata take priority
    # over conda records, including when pip has overwritten a conda package.
    versions["python"] = ".".join(map(str, sys.version_info[:3]))
    for name in MINIMUMS.keys() - {"python", "ca-certificates", "pixi"}:
        try:
            versions[name] = importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:
            pass
    return versions


def check_installed():
    versions = installed_versions()
    errors = check_versions(versions)
    try:
        from pip._vendor import certifi

        versions["pip._vendor.certifi"] = certifi.__version__
        if version_tuple(certifi.__version__) < version_tuple(MINIMUMS["certifi"]):
            errors.append(f"pip's vendored certifi {certifi.__version__} is below {MINIMUMS['certifi']}")
        if not Path(certifi.where()).is_file():
            errors.append("pip's vendored certificate bundle is missing")
    except (ImportError, AttributeError, ValueError) as exc:
        errors.append(f"cannot validate pip's vendored certifi: {exc}")
    return versions, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("environment", nargs="?", type=Path,
                        default=Path(__file__).resolve().parents[1] / "environments/analysis3/environment.yml")
    parser.add_argument("--installed", action="store_true", help="check the running analysis3 prefix and pip's vendored bundle")
    args = parser.parse_args()
    if args.installed:
        versions, errors = check_installed()
    else:
        versions, errors = export_versions(args.environment.read_text())
        errors += check_versions(versions)
    for name, version in sorted(versions.items()):
        print(f"{name}: {version}")
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
