"""Check that broken-labelled packages in pixi.lock match pixi.toml declarations.

Writes a markdown report and exits non-zero if the set of packages resolved from a
``/label/broken`` channel in the lock differs from the set explicitly pinned to a
broken channel in pixi.toml.
"""

import re
import tomllib
from pathlib import Path

BROKEN_MARKER = "/label/broken"
BROKEN_URL_RE = re.compile(r"https://[^\s\"']+/label/broken/[^\s\"']+")

ENV_DIR = Path(__file__).resolve().parent
PIXI_TOML = ENV_DIR / "pixi.toml"
LOCKFILE = ENV_DIR / "pixi.lock"
MARKDOWN_OUTPUT = Path("/tmp/broken-packages.md")


def declared_broken(pixi_toml: Path) -> set[str]:
    """Names of dependencies pinned to a broken-labelled channel anywhere in pixi.toml."""
    declared: set[str] = set()

    def walk(node: object) -> None:
        if isinstance(node, dict):
            for name, spec in node.items():
                if isinstance(spec, dict) and BROKEN_MARKER in str(
                    spec.get("channel", "")
                ):
                    declared.add(name)
                walk(spec)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(tomllib.loads(pixi_toml.read_text()))
    return declared


def resolved_broken(lockfile: Path) -> dict[str, str]:
    """Map package name -> URL for every package resolved from a broken channel in the lock."""
    resolved: dict[str, str] = {}
    for url in BROKEN_URL_RE.findall(lockfile.read_text()):
        filename = url.rsplit("/", 1)[-1]
        stem = filename.removesuffix(".conda").removesuffix(".tar.bz2")
        resolved[stem.rsplit("-", 2)[0]] = url
    return resolved


def render_markdown(declared: set[str], resolved: dict[str, str]) -> tuple[str, bool]:
    unexpected = sorted(resolved.keys() - declared)
    missing = sorted(declared - resolved.keys())
    ok = not unexpected and not missing

    lines = ["## Pixi broken package check", ""]
    if resolved:
        lines.append("Packages resolved from `/label/broken` channels in `pixi.lock`:")
        lines += [f"- `{name}` — `{resolved[name]}`" for name in sorted(resolved)]
    else:
        lines.append(
            "No packages resolved from `/label/broken` channels in `pixi.lock`."
        )

    if unexpected:
        lines += ["", "**Unexpected** (in lock, not declared in `pixi.toml`):"]
        lines += [f"- `{name}`" for name in unexpected]
    if missing:
        lines += ["", "**Missing** (declared in `pixi.toml`, absent from lock):"]
        lines += [f"- `{name}`" for name in missing]

    verdict = "✅ match" if ok else "❌ mismatch"
    lines += ["", f"{verdict}: broken-label packages in `pixi.lock` vs `pixi.toml`."]
    return "\n".join(lines) + "\n", ok


def main() -> int:
    markdown, ok = render_markdown(declared_broken(PIXI_TOML), resolved_broken(LOCKFILE))
    MARKDOWN_OUTPUT.write_text(markdown)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
