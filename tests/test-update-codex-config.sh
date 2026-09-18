#!/bin/sh
set -eu

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
updater=$base_dir/bin/update-codex-config
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

printf '%s\n' 'new workflow policy' 'second line' >"$tmp/instructions.md"
printf '%s\n' \
  'model = "gpt-test"' \
  'developer_instructions = "old"' \
  '' \
  '[projects."/work"]' \
  'trust_level = "trusted"' >"$tmp/config.toml"

python3 "$updater" "$tmp/config.toml" "$tmp/instructions.md"
[ -f "$tmp/config.toml.lock" ]
[ "$(stat -c '%a' "$tmp/config.toml.lock")" = 600 ]
python3 - "$tmp/config.toml" <<'PY'
from pathlib import Path
import sys
import tomlkit

data = tomlkit.parse(Path(sys.argv[1]).read_text())
assert data["model"] == "gpt-test"
assert data["developer_instructions"] == "new workflow policy\nsecond line\n"
assert data["model_context_window"] == 872000
assert data["model_auto_compact_token_limit"] == 700000
assert data["projects"]["/work"]["trust_level"] == "trusted"
PY

printf '%s\n' \
  'developer_instructions = """' \
  'old line 1' \
  '[not-a-table]' \
  'old line 2 with \""" escaped quotes' \
  '"""' \
  'approval_policy = "on-request"' >"$tmp/multiline.toml"
python3 "$updater" "$tmp/multiline.toml" "$tmp/instructions.md"
python3 - "$tmp/multiline.toml" <<'PY'
from pathlib import Path
import sys
import tomlkit

data = tomlkit.parse(Path(sys.argv[1]).read_text())
assert data["developer_instructions"] == "new workflow policy\nsecond line\n"
assert data["model_context_window"] == 872000
assert data["model_auto_compact_token_limit"] == 700000
assert data["approval_policy"] == "on-request"
PY

printf '%s\n' 'contains """ and literal triple quotes: '\'''\'''\''' >>"$tmp/instructions.md"
python3 "$updater" "$tmp/multiline.toml" "$tmp/instructions.md"
python3 "$updater" --verify "$tmp/multiline.toml" "$tmp/instructions.md"

python3 "$updater" "$tmp/new.toml" "$tmp/instructions.md"
printf '%s\n' \
  '[projects."/table-only"]' \
  'trust_level = "trusted"' >"$tmp/table-only.toml"
chmod 640 "$tmp/table-only.toml"
python3 - "$tmp/table-only.toml" <<'PY'
import os
import sys

os.setxattr(sys.argv[1], "user.server-policy-test", b"preserved")
PY
metadata_before=$(stat -c '%u:%g:%a' "$tmp/table-only.toml")
python3 "$updater" "$tmp/table-only.toml" "$tmp/instructions.md"
[ "$(stat -c '%u:%g:%a' "$tmp/table-only.toml")" = "$metadata_before" ]
python3 - "$tmp/table-only.toml" <<'PY'
from pathlib import Path
import os
import sys
import tomlkit

data = tomlkit.parse(Path(sys.argv[1]).read_text())
assert data["developer_instructions"] == "new workflow policy\nsecond line\ncontains \"\"\" and literal triple quotes: '''\n"
assert data["model_context_window"] == 872000
assert data["model_auto_compact_token_limit"] == 700000
assert data["projects"]["/table-only"]["trust_level"] == "trusted"
assert os.getxattr(sys.argv[1], "user.server-policy-test") == b"preserved"
PY

inode_before=$(stat -c '%d:%i:%Y:%Z' "$tmp/table-only.toml")
python3 "$updater" "$tmp/table-only.toml" "$tmp/instructions.md"
[ "$(stat -c '%d:%i:%Y:%Z' "$tmp/table-only.toml")" = "$inode_before" ]

printf '%s\n' 'model = "gpt-test"' >"$tmp/check.toml"
cp "$tmp/check.toml" "$tmp/check.before"
python3 "$updater" --check "$tmp/check.toml" "$tmp/instructions.md"
cmp "$tmp/check.before" "$tmp/check.toml"
[ ! -e "$tmp/check-missing.toml" ]
python3 "$updater" --check "$tmp/check-missing.toml" "$tmp/instructions.md"
[ ! -e "$tmp/check-missing.toml" ]

printf '%s\n' 'invalid = [' >"$tmp/broken.toml"
cp "$tmp/broken.toml" "$tmp/broken.before"
if python3 "$updater" "$tmp/broken.toml" "$tmp/instructions.md" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL malformed Codex TOML was overwritten' >&2
  exit 1
fi
cmp "$tmp/broken.before" "$tmp/broken.toml"

ln -s "$tmp/config.toml" "$tmp/config-link.toml"
if python3 "$updater" "$tmp/config-link.toml" "$tmp/instructions.md" >/dev/null 2>&1; then
  printf '%s\n' 'FAIL symlinked Codex config was replaced' >&2
  exit 1
fi
[ -L "$tmp/config-link.toml" ]

printf '%s\n' 'model = "before-race"' >"$tmp/race.toml"
python3 - "$updater" "$tmp/race.toml" "$tmp/instructions.md" <<'PY'
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path
import sys

loader = SourceFileLoader("update_codex_config", sys.argv[1])
spec = spec_from_loader(loader.name, loader)
assert spec is not None
module = module_from_spec(spec)
sys.modules[spec.name] = module
loader.exec_module(module)
config = Path(sys.argv[2])
instructions = Path(sys.argv[3])
read_snapshot = module.read_config_snapshot
calls = 0

def racing_snapshot(path):
    global calls
    snapshot = read_snapshot(path)
    calls += 1
    if calls == 1:
        path.write_text('model = "external-writer"\n', encoding="utf-8")
    return snapshot

module.read_config_snapshot = racing_snapshot
sys.argv = [sys.argv[1], str(config), str(instructions)]
try:
    module.main()
except RuntimeError as exc:
    assert "external content was preserved" in str(exc)
else:
    raise AssertionError("stale Codex config snapshot was overwritten")
assert config.read_text(encoding="utf-8") == 'model = "external-writer"\n'
PY

printf '%s\n' 'model = "before-exchange"' >"$tmp/exchange-race.toml"
python3 - "$updater" "$tmp/exchange-race.toml" "$tmp/instructions.md" <<'PY'
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path
import sys

loader = SourceFileLoader("update_codex_config_exchange", sys.argv[1])
spec = spec_from_loader(loader.name, loader)
assert spec is not None
module = module_from_spec(spec)
sys.modules[spec.name] = module
loader.exec_module(module)
config = Path(sys.argv[2])
instructions = Path(sys.argv[3])
real_renameat2 = module.renameat2
injected = False

def racing_rename(source, target, flags):
    global injected
    if flags == 2 and not injected:
        config.write_text('model = "last-moment-writer"\n', encoding="utf-8")
        injected = True
    return real_renameat2(source, target, flags)

module.renameat2 = racing_rename
sys.argv = [sys.argv[1], str(config), str(instructions)]
try:
    module.main()
except RuntimeError as exc:
    assert "external content was preserved" in str(exc)
else:
    raise AssertionError("last-moment Codex config update was overwritten")
assert config.read_text(encoding="utf-8") == 'model = "last-moment-writer"\n'
PY

printf '%s\n' 'model = "before-open-fd"' >"$tmp/open-fd.toml"
python3 - "$updater" "$tmp/open-fd.toml" "$tmp/instructions.md" <<'PY'
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path
import os
import sys
import tomlkit

loader = SourceFileLoader("update_codex_config_open_fd", sys.argv[1])
spec = spec_from_loader(loader.name, loader)
assert spec is not None
module = module_from_spec(spec)
sys.modules[spec.name] = module
loader.exec_module(module)
config = Path(sys.argv[2])
instructions = Path(sys.argv[3])
with config.open("r+", encoding="utf-8") as old_handle:
    sys.argv = [sys.argv[1], str(config), str(instructions)]
    module.main()
    recovery_files = list(config.parent.glob(f".{config.name}.recovery-*"))
    assert len(recovery_files) == 1
    old_handle.seek(0)
    old_handle.truncate()
    old_handle.write('model = "late-open-fd-writer"\n')
    old_handle.flush()
    os.fsync(old_handle.fileno())
recovery_files = list(config.parent.glob(f".{config.name}.recovery-*"))
assert recovery_files[0].read_text(encoding="utf-8") == 'model = "late-open-fd-writer"\n'
document = tomlkit.parse(config.read_text(encoding="utf-8"))
assert document["developer_instructions"].startswith("new workflow policy")
PY

printf '%s\n' 'model = "lock-test"' >"$tmp/locked.toml"
python3 - "$updater" "$tmp/locked.toml" "$tmp/instructions.md" <<'PY'
from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
import fcntl
from pathlib import Path
import subprocess
import sys

updater, config, instructions = sys.argv[1:]
loader = SourceFileLoader("update_codex_config_lock", updater)
spec = spec_from_loader(loader.name, loader)
assert spec is not None
module = module_from_spec(spec)
sys.modules[spec.name] = module
loader.exec_module(module)
lock = Path(f"{config}.lock")
probe = """
import fcntl, pathlib, sys
with pathlib.Path(sys.argv[1]).open('r+') as handle:
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit(0)
    raise SystemExit(1)
"""
with module.config_update_lock(Path(config)):
    result = subprocess.run([sys.executable, "-c", probe, str(lock)], check=False)
    assert result.returncode == 0, "sidecar lock did not exclude another updater"
assert subprocess.run([sys.executable, updater, config, instructions], check=False).returncode == 0
PY

printf '%s\n' 'Codex TOML update tests passed'
