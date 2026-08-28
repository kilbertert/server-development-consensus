#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
version = (root / "VERSION").read_text().strip()
assert re.fullmatch(r"0|[1-9]\d*\.\d+\.\d+", version), version
contract = json.loads((root / "policy/afk-contract.json").read_text())
assert contract["consensus_version"] == version
assert contract["afk_template_compatibility"] == ">=1.0.0 <2.0.0"
assert set(contract["non_exceptionable_invariants"]).issubset(contract["invariants"])
assert contract["non_exceptionable_invariants"]
assert len(contract["invariants"]) == len(set(contract["invariants"]))
print("AFK contract passed")
PY
