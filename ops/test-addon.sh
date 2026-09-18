#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
LUA="${LUA:-$(command -v lua5.1 || command -v luajit || command -v lua || true)}"
if [ -z "$LUA" ]; then
  echo "Install Lua 5.1 or LuaJIT to run the tests." >&2
  exit 2
fi
for api in modern legacy; do
  FDC_TOOLTIP_API="$api" "$LUA" addon/tests/run.lua "$@"
done
"$LUA" addon/tests/safety.lua
"$LUA" addon/tests/load.lua
