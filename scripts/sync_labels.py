#!/usr/bin/env python3
"""Push .github/labels.yml to the repository's label set.

Labels are the one piece of repository configuration GitHub offers no way to
review. They get clicked into existence during a triage session, spelled three
different ways, and a year later nobody can say which of `docs`, `doc` and
`documentation` is the real one. Keeping them in a file makes adding one a pull
request like any other.

The script creates and updates. It never deletes, and that is deliberate:
removing a label strips it from every issue that ever carried it, and GitHub
does not give that history back. Labels on the repository that are not in the
file are reported and left alone.

Needs `gh` authenticated with a token that has `issues: write`.

    python scripts/sync_labels.py --dry-run     # print the plan, change nothing
    python scripts/sync_labels.py               # apply it
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import subprocess
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
LABELS_FILE = ROOT / ".github" / "labels.yml"

# GitHub's own limits. Exceeding either is a 422 that reads like a bad token.
MAX_NAME = 50
MAX_DESCRIPTION = 100

HEX = re.compile(r"^[0-9a-fA-F]{6}$")


def load() -> list[dict[str, str]]:
    """Read the file and refuse anything GitHub would reject."""
    doc = yaml.safe_load(LABELS_FILE.read_text(encoding="utf-8"))
    if not isinstance(doc, dict) or not isinstance(doc.get("labels"), list):
        sys.exit(f"{LABELS_FILE}: expected a top-level `labels:` list")

    labels: list[dict[str, str]] = []
    errors: list[str] = []
    seen: set[str] = set()

    for i, entry in enumerate(doc["labels"]):
        where = f"labels[{i}]"
        if not isinstance(entry, dict):
            errors.append(f"{where}: not a mapping")
            continue

        name = entry.get("name")
        if not isinstance(name, str) or not name.strip():
            errors.append(f"{where}: missing name")
            continue
        where = f"{name!r}"
        if len(name) > MAX_NAME:
            errors.append(f"{where}: name is {len(name)} chars, max {MAX_NAME}")
        # GitHub matches label names case-insensitively; two entries differing
        # only in case would fight each other on every run.
        if name.lower() in seen:
            errors.append(f"{where}: duplicate name")
        seen.add(name.lower())

        color = str(entry.get("color", "")).lstrip("#")
        if not HEX.match(color):
            errors.append(f"{where}: color {color!r} is not 6 hex digits")

        description = entry.get("description", "") or ""
        if not isinstance(description, str):
            errors.append(f"{where}: description is not a string")
            description = ""
        elif len(description) > MAX_DESCRIPTION:
            errors.append(
                f"{where}: description is {len(description)} chars, "
                f"max {MAX_DESCRIPTION}"
            )

        unknown = set(entry) - {"name", "color", "description"}
        if unknown:
            errors.append(f"{where}: unknown keys {sorted(unknown)}")

        labels.append(
            {
                "name": name,
                "color": color.lower(),
                "description": description,
            }
        )

    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        sys.exit(1)
    if not labels:
        sys.exit(f"{LABELS_FILE}: no labels defined")
    return labels


def gh(*args: str, check: bool = True) -> str:
    result = subprocess.run(
        ["gh", *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if check and result.returncode != 0:
        sys.exit(f"gh {' '.join(args)} failed:\n{result.stderr.strip()}")
    return result.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print what would change and exit without touching the repository",
    )
    parser.add_argument(
        "--repo",
        default=os.environ.get("GITHUB_REPOSITORY"),
        help="owner/name. Defaults to $GITHUB_REPOSITORY, then to gh's guess.",
    )
    args = parser.parse_args()

    wanted = load()
    print(f"{LABELS_FILE.relative_to(ROOT).as_posix()}: {len(wanted)} label(s), valid")

    if args.dry_run and not args.repo:
        # Validation alone is useful in a pre-commit hook, where there is no
        # repository to talk to and no token to talk with.
        print("dry run without a repository: validated the file only")
        return 0

    repo = args.repo or gh("repo", "view", "--json", "nameWithOwner",
                           "-q", ".nameWithOwner").strip()
    print(f"repository: {repo}")

    existing_raw = gh("api", "--paginate", f"repos/{repo}/labels")
    # --paginate concatenates one JSON array per page; parse them individually.
    existing: dict[str, dict[str, str]] = {}
    decoder = json.JSONDecoder()
    index = 0
    while index < len(existing_raw):
        if existing_raw[index].isspace():
            index += 1
            continue
        page, offset = decoder.raw_decode(existing_raw, index)
        for label in page:
            existing[label["name"].lower()] = label
        index = offset

    created = updated = unchanged = 0

    for label in wanted:
        current = existing.get(label["name"].lower())
        if current is None:
            print(f"  + {label['name']}")
            created += 1
            if not args.dry_run:
                gh(
                    "api", "--method", "POST", f"repos/{repo}/labels",
                    "-f", f"name={label['name']}",
                    "-f", f"color={label['color']}",
                    "-f", f"description={label['description']}",
                    "--silent",
                )
            continue

        drift = []
        if (current.get("color") or "").lower() != label["color"]:
            drift.append(f"color {current.get('color')} -> {label['color']}")
        if (current.get("description") or "") != label["description"]:
            drift.append("description")
        if current["name"] != label["name"]:
            drift.append(f"name {current['name']} -> {label['name']}")

        if not drift:
            unchanged += 1
            continue

        print(f"  ~ {label['name']}: {', '.join(drift)}")
        updated += 1
        if not args.dry_run:
            gh(
                "api", "--method", "PATCH",
                f"repos/{repo}/labels/{current['name']}",
                "-f", f"new_name={label['name']}",
                "-f", f"color={label['color']}",
                "-f", f"description={label['description']}",
                "--silent",
            )

    wanted_names = {label["name"].lower() for label in wanted}
    extra = sorted(
        current["name"] for key, current in existing.items()
        if key not in wanted_names
    )
    if extra:
        print(f"\nnot in {LABELS_FILE.name}, left untouched: {', '.join(extra)}")
        print("Delete one by hand only if you accept losing it from old issues.")

    verb = "would " if args.dry_run else ""
    print(f"\n{verb}created {created}, {verb}updated {updated}, {unchanged} unchanged")
    return 0


if __name__ == "__main__":
    sys.exit(main())
