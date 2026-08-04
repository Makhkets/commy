#!/usr/bin/env python3
"""Compare the Dart and Kotlin halves of the platform-channel contract.

Neither compiler can see the other side. A renamed channel, a dropped method or
a state string spelled differently is invisible until a button quietly stops
working on a real device — which is the most expensive kind of bug this project
can ship, because it only reproduces where nobody is attached to a debugger.

Both sides deliberately keep their strings in one file each, so the check is a
matter of reading two files and diffing sets. Values are built by interpolation
(`"$NAMESPACE/core"`), so grepping for a whole literal finds nothing; we compare
the *suffixes* and the plain constants instead.

Run it directly, or let CI do it:

    python scripts/check_wire_contract.py
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DART_DIR = ROOT / "packages" / "commy_core" / "lib" / "src" / "wire"
KOTLIN = ROOT / (
    "apps/commy/android/app/src/main/kotlin/dev/commy/app/wire/Wire.kt"
)

# Channels the native side may add for its own purposes. /intents carries
# deep links and Quick Settings taps — inputs from the Android system that have
# no counterpart in the tunnel protocol, so Dart is free to ignore it.
KOTLIN_ONLY_CHANNELS = {"intents"}

# `checking` is derived on the Dart side from the first url test after a
# connection comes up. The native side never sends it and has no constant for
# it, and that asymmetry is the design, not a gap.
DART_ONLY_STATES = {"checking"}

# Keys the native side owns alone. Each one is deliberate; anything not on this
# list that appears on only one side is a real disagreement.
KOTLIN_ONLY_KEYS = {
    # /intents payloads. Dart reads that channel with its own decoder because
    # the events are Android-shaped, not tunnel-shaped.
    "kind",
    "uri",
    "text",
    # proxies(): informational. Dart works out whether a group is switchable
    # from its `type`, so it never reads this field — but Kotlin sends it,
    # because it is free there and a future bulk latency test will want it.
    "selectable",
}


def dart_values(filename: str, pattern: str) -> set[str]:
    path = DART_DIR / filename
    if not path.exists():
        sys.exit(f"missing: {path}")
    return set(re.findall(pattern, path.read_text(encoding="utf-8")))


def kotlin_values(section: str, pattern: str) -> set[str]:
    text = KOTLIN.read_text(encoding="utf-8")
    match = re.search(
        rf"object {section} \{{(.*?)\n    \}}", text, re.DOTALL
    )
    if not match:
        sys.exit(f"could not find `object {section}` in {KOTLIN.name}")
    return set(re.findall(pattern, match.group(1)))


def compare(label: str, dart: set[str], kotlin: set[str],
            dart_only: set[str] = frozenset(),
            kotlin_only: set[str] = frozenset()) -> bool:
    missing_in_kotlin = dart - kotlin - dart_only
    missing_in_dart = kotlin - dart - kotlin_only
    if not missing_in_kotlin and not missing_in_dart:
        print(f"  ok  {label:12s} {len(dart & kotlin)} shared")
        return True
    print(f"  FAIL {label}")
    for item in sorted(missing_in_kotlin):
        print(f"       {item!r} is in Dart but not in Kotlin")
    for item in sorted(missing_in_dart):
        print(f"       {item!r} is in Kotlin but not in Dart")
    return False


def main() -> int:
    print("wire contract: packages/commy_core <-> apps/commy/android")

    ok = True

    # Channel suffixes: '$namespace/core' -> 'core'
    ok &= compare(
        "channels",
        dart_values("wire_channels.dart", r"\$namespace/([a-z]+)"),
        kotlin_values("Channels", r"\$NAMESPACE/([a-z]+)"),
        kotlin_only=KOTLIN_ONLY_CHANNELS,
    )

    ok &= compare(
        "methods",
        dart_values("wire_methods.dart", r"=\s*'([a-zA-Z]+)'"),
        kotlin_values("Methods", r'=\s*"([a-zA-Z]+)"'),
    )

    ok &= compare(
        "states",
        dart_values("wire_states.dart", r"=\s*'([a-z]+)'"),
        kotlin_values("States", r'=\s*"([a-z]+)"'),
        dart_only=DART_ONLY_STATES,
    )

    ok &= compare(
        "error codes",
        dart_values("wire_error_codes.dart", r"=\s*'([a-z_]+)'"),
        kotlin_values("Errors", r'=\s*"([a-z_]+)"'),
    )

    ok &= compare(
        "json keys",
        dart_values("wire_keys.dart", r"=\s*'([a-zA-Z]+)'"),
        kotlin_values("Keys", r'=\s*"([a-zA-Z]+)"'),
        kotlin_only=KOTLIN_ONLY_KEYS,
    )

    if not ok:
        print(
            "\nThe two sides of the platform channel disagree. "
            "See packages/commy_core/docs/wire-protocol.md."
        )
        return 1
    print("both sides agree")
    return 0


if __name__ == "__main__":
    sys.exit(main())
