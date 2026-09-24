#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if command -v python3 >/dev/null 2>&1; then
  exec python3 "$ROOT/server.py" "$@"
fi

if command -v python >/dev/null 2>&1; then
  exec python "$ROOT/server.py" "$@"
fi

echo "PatchScope needs Python 3." >&2
exit 1
