#!/usr/bin/env bash
# Build an unsigned iOS app with matching numeric app/extension versions.
# Build the pinned native framework with scripts/build_core.sh apple first.
set -euo pipefail
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
read -r COMMY_IOS_VERSION COMMY_IOS_BUILD < <(python3 - "$REPO_ROOT/apps/commy/pubspec.yaml" <<'PY'
import re
import sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
match = re.search(r'^version:\s*(\d+\.\d+\.\d+)(?:-[^+\s]+)?\+(\d+)\s*$', text, re.M)
if not match:
    sys.exit('Expected version: major.minor.patch[-suffix]+build in pubspec.yaml')
print(*match.groups())
PY
)
cd "$REPO_ROOT/apps/commy"
"${FLUTTER_BIN:-flutter}" build ios --release --no-codesign \
  --build-name="$COMMY_IOS_VERSION" --build-number="$COMMY_IOS_BUILD" "$@"
