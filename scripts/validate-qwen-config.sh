#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CFG="${1:-${ROOT_DIR}/templates/qwen-settings.json}"
ENV_FILE="${2:-}"

pass=0
fail=0

ok() { echo "[PASS] $*"; pass=$((pass + 1)); }
ng() { echo "[FAIL] $*"; fail=$((fail + 1)); }

echo "=== Qwen config validation ==="
echo "File: $CFG"

[[ -f "$CFG" ]] || { ng "file not found"; exit 1; }

if command -v jq >/dev/null 2>&1; then
  jq empty "$CFG" && ok "JSON syntax (jq)" || ng "JSON syntax (jq)"
else
  python3 -m json.tool "$CFG" >/dev/null && ok "JSON syntax (python)" || ng "JSON syntax (python)"
fi

if python3 - "$CFG" << 'PY'; then
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
data = json.loads(p.read_text(encoding="utf-8"))

for k in ("modelProviders", "security", "model"):
    assert k in data, f"missing: {k}"

assert data["security"]["auth"]["selectedType"] == "openai"

models = data["modelProviders"]["openai"]
assert models, "modelProviders.openai empty"

ids = [m["id"] for m in models]
assert len(ids) == len(set(ids)), "duplicate model ids"

default_model = data["model"]["name"]
assert default_model in ids, f"model.name {default_model} not in providers"

env_keys = {m["envKey"] for m in models}
for m in models:
    assert m.get("baseUrl"), f"{m['id']} missing baseUrl"

print(f"models={len(models)} default={default_model} envKeys={sorted(env_keys)}")
PY
  ok "schema checks"
else
  ng "schema checks"
fi

if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
  echo "--- .env ---"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[A-Z_]+=.+ ]] || continue
    k="${line%%=*}"
    v="${line#*=}"
    if [[ -n "$v" && "$v" != "your-fangzhou-key" && "$v" != "your-bailian-key" ]]; then
      ok "env $k set"
    else
      ng "env $k empty or placeholder"
    fi
  done < "$ENV_FILE"
fi

export PATH="${HOME}/.local/bin:${PATH}"
if command -v qwen >/dev/null 2>&1; then
  qwen --version >/dev/null 2>&1 && ok "qwen CLI" || ng "qwen CLI"
  if [[ -f "${HOME}/.qwen/settings.json" ]]; then
    echo "--- qwen auth status ---"
    qwen auth status 2>&1 | head -8 || true
  fi
else
  echo "[SKIP] qwen CLI not installed"
fi

echo "=== Result: ${pass} passed, ${fail} failed ==="
[[ $fail -eq 0 ]]
