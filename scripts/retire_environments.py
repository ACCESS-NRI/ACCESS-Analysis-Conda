#!/usr/bin/env python3
"""Retire old deployed SquashFS versions. Dry run unless --apply is given."""

import argparse
import fcntl
import json
import os
import re
import sys
from pathlib import Path


def link_target_version(path, prefix):
    if not path.is_symlink():
        return None
    target = Path(os.readlink(path)).name
    return target if target.startswith(prefix) else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--admin", type=Path, required=True)
    parser.add_argument("--environment", required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--protect", action="append", default=[],
                        help="additional full version to keep (repeatable)")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    if not re.fullmatch(r"[a-z][a-z0-9_-]*", args.environment):
        parser.error("invalid environment name")
    if not args.base.is_absolute() or not args.admin.is_absolute():
        parser.error("base and admin must be absolute paths")
    settings = json.loads(args.config.read_text())
    keep = settings["keep"]
    pinned = set(settings.get("pinned", [])) | set(args.protect)
    if not isinstance(keep, int) or isinstance(keep, bool) or keep < 1:
        parser.error("keep must be a positive integer")
    prefix = args.environment + "-"
    version_re = re.compile(r"^" + re.escape(prefix) + r"(\d{2})\.(\d{2})$")
    if any(not version_re.fullmatch(name) for name in pinned):
        parser.error("pinned entries must be full, dated environment versions")

    envs = args.base / "apps/med_conda/envs"
    modules = args.base / "modules/conda"
    scripts = args.base / "apps/med_conda_scripts"
    retired = args.admin / "retired-environments"
    if not envs.is_dir() or not modules.is_dir() or not scripts.is_dir():
        parser.error("expected deployed envs, modules and scripts directories")
    if retired.exists() and not retired.is_dir():
        parser.error("retirement destination is not a directory")

    versions = {}
    for image in envs.glob(prefix + "*.sqsh"):
        version = image.name.removesuffix(".sqsh")
        match = version_re.fullmatch(version)
        if match and image.is_file() and not image.is_symlink():
            versions[version] = tuple(map(int, match.groups()))
        else:
            print(f"Skipping unrecognized image: {image}", file=sys.stderr)

    newest = set(sorted(versions, key=lambda v: versions[v], reverse=True)[:keep])
    protected = newest | pinned
    # A live alias wins over the retention count, including stable/unstable.
    for alias in (args.environment, args.environment + "-unstable"):
        for parent, suffix in ((envs, ""), (scripts, ".d")):
            target = link_target_version(parent / (alias + suffix), prefix)
            if target:
                protected.add(target.removesuffix(".d"))
    modulerc = modules / ".modulerc"
    if modulerc.exists():
        for line in modulerc.read_text().splitlines():
            match = re.match(r"\s*module-version\s+conda/(\S+)", line)
            if match and match.group(1).startswith(prefix):
                protected.add(match.group(1))

    pending = set()
    if retired.is_dir():
        pending = {entry.name for entry in retired.iterdir()
                   if entry.is_dir() and (entry / ".incomplete").exists()
                   and version_re.fullmatch(entry.name)}
    candidates = sorted((set(versions) - protected) | (pending - protected),
                        key=lambda v: tuple(map(int, version_re.fullmatch(v).groups())))
    print(f"Keeping newest {keep}: {', '.join(sorted(newest)) or '(none)'}")
    print(f"Protected by pin or alias: {', '.join(sorted(protected - newest)) or '(none)'}")
    print(f"To retire: {', '.join(candidates) or '(none)'}")
    if not args.apply:
        return 0

    retired.mkdir(parents=True, exist_ok=True)
    with (retired / ".lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for version in candidates:
            destination = retired / version
            if destination.exists() and not (destination / ".incomplete").exists():
                raise RuntimeError(f"Existing retirement directory needs review: {destination}")
            destination.mkdir(exist_ok=True)
            marker = destination / ".incomplete"
            marker.touch()
            entries = (
                (envs / (version + ".sqsh"), "image.sqsh"),
                (envs / version, "environment-link"),
                (modules / version, "module-link"),
                (modules / ("." + version), "module-insert"),
                (scripts / (version + ".d"), "scripts.d"),
            )
            for source, label in entries:
                target = destination / label
                if target.exists() or target.is_symlink():
                    if source.exists() or source.is_symlink():
                        raise RuntimeError(f"Both deployed and retired copies exist: {source}")
                    continue  # Resume a partially completed retirement.
                if source.exists() or source.is_symlink():
                    source.rename(target)  # Same-filesystem move; fail safely otherwise.
                    print(f"Moved {source} -> {target}")
            if not (destination / "image.sqsh").is_file():
                raise RuntimeError(f"Retired image is missing: {destination / 'image.sqsh'}")
            marker.unlink()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError) as error:
        print(f"Retirement failed: {error}", file=sys.stderr)
        sys.exit(1)
