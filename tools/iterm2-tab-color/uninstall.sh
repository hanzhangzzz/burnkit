#!/usr/bin/env bash
# Compatibility wrapper. Use `bin/burnkit uninstall tabs` from the repo root.
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

printf 'WARN tools/iterm2-tab-color/uninstall.sh is a compatibility wrapper; prefer: %s\n' "$REPO_ROOT/bin/burnkit uninstall tabs"
exec "$SCRIPT_DIR/uninstall-core.sh" "$@"
