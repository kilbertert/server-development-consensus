#!/usr/bin/env bash
set -Eeuo pipefail

# Tests for dev-host-auth-audit.
#
# 这个工具的真实输入有三样：主机清单（谁要查、按什么类型查）、dev-host（怎么连）、
# 目标机上的 sshd 输出（真相）。三样都必须能注入，否则测试会依赖"此刻哪台机器
# 在线"。
#   DEV_HOST_REGISTRY          — 假主机清单
#   DEV_HOST_AUTH_SSH_TOOL     — 假 dev-host（按主机名回放预设输出）
#   DEV_HOST_AUTH_PROJECT_DECL — 假项目声明
#
# 重点覆盖的不是 happy path，而是两类会被误报的结果：
#   weakened —— 口令登录被放开（必须红）
#   unknown  —— 连不上/解不出（必须橙，且不得计入通过）

trap 'status=$?; printf "FAIL test-dev-host-auth-audit.sh:%s command=%q status=%s\n" "$LINENO" "$BASH_COMMAND" "$status" >&2; exit "$status"' ERR

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tool=$base_dir/bin/dev-host-auth-audit
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

failures=0
check() {
  local label=$1 expected=$2 actual=$3
  if [[ $expected == "$actual" ]]; then
    printf 'ok %s\n' "$label"
  else
    printf 'FAIL %s: expected %q got %q\n' "$label" "$expected" "$actual" >&2
    failures=$((failures + 1))
  fi
}

# ---------- 假主机清单 ----------
cat >"$tmp/registry.toml" <<'TOML'
[hosts.linux-good]
role = "service-host"
owner = "claude"
access = "ssh"
hostkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

[hosts.linux-open]
role = "service-host"
owner = "claude"
access = "ssh"
hostkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

[hosts.win-box]
role = "development-host"
owner = "claude"
access = "ssh"
auth_type = "windows-sshd"
hostkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

[hosts.rdp-only]
role = "project-production-host"
owner = "claude"
access = "rdp"

[hosts.linux-known]
role = "service-host"
owner = "claude"
access = "ssh"
known_exception = "公司主机,非本账号可改;已报告权属方"
hostkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

[hosts.retired-one]
role = "service-host"
owner = "claude"
access = "ssh"
status = "retired"
hostkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
TOML

: >"$tmp/project.toml"
export DEV_HOST_REGISTRY=$tmp/registry.toml
export DEV_HOST_AUTH_PROJECT_DECL=$tmp/project.toml

# ---------- 假 dev-host ----------
# 按 TARGET（第 2 个位置参数）决定输出；模拟真实 dev-host 的 argv 形态：
#   exec <target> --project <decl> [--allow-service-exec] [--timeout N] -- <cmd>
cat >"$tmp/fake-dev-host" <<'SH'
#!/usr/bin/env bash
set -u
[ "${1:-}" = exec ] || { echo "fake: expected exec" >&2; exit 64; }
# 模拟真实 ssh：它会读 stdin。如果调用方没有 </dev/null，这里的 read
# 会吃掉外层 while 循环的输入 —— 正是要回归的那个 bug。
if [ -n "${FAKE_STEAL_STDIN:-}" ]; then
  read -r _stolen || true
fi
target=$2
mode=${FAKE_MODE:-ok}
case "$target" in
  linux-good)
    case $mode in
      ok)        echo "passwordauthentication no" ;;
      weakened)  echo "passwordauthentication yes" ;;
      offline)   exit 255 ;;
      garbage)   echo "some other output" ;;
    esac ;;
  linux-known)
    echo "passwordauthentication yes" ;;
  linux-open)
    case $mode in
      weakened) echo "passwordauthentication yes" ;;
      offline)  exit 255 ;;
      garbage)  echo "unexpected" ;;
      *)        echo "passwordauthentication no" ;;
    esac ;;
  win-box)
    # Windows 分支走 powershell，真实输出是整行配置
    case $mode in
      offline)  exit 255 ;;
      weakened) echo "PasswordAuthentication yes (default)" ;;
      *)        echo "PasswordAuthentication no" ;;
    esac ;;
  *) exit 255 ;;
esac
SH
chmod +x "$tmp/fake-dev-host"
export DEV_HOST_AUTH_SSH_TOOL=$tmp/fake-dev-host

run() {  # run [--check|--json] [targets...]
  RUN_RC=0
  RUN_OUT=$("$tool" "$@" 2>&1) || RUN_RC=$?
}

# ---------- 1. 全绿 ----------
run
check "all-good exit 0" 0 "$RUN_RC"
[[ $RUN_OUT == *"ok"* ]] || { printf 'FAIL all-good: no ok verdict\n%s\n' "$RUN_OUT" >&2; failures=$((failures + 1)); }
# RDP 与 retired 必须显示为 skipped，而不是通过
[[ $RUN_OUT == *skipped*rdp-only* || $RUN_OUT == *rdp-only*skipped* ]] || {
  printf 'FAIL rdp target not shown as skipped\n%s\n' "$RUN_OUT" >&2; failures=$((failures + 1)); }

# ---------- 2. 口令被放开 -> 非零 ----------
# 注意：这一组必须排除 linux-known（它带 known_exception，不该判红），
# 所以显式只查 linux-open。
FAKE_MODE=weakened run --check linux-open
[ "$RUN_RC" -ne 0 ] || { printf 'FAIL weakened should exit non-zero\n' >&2; failures=$((failures + 1)); }
[[ $RUN_OUT == *"FAIL sshd password authentication is ENABLED on linux-open"* ]] || {
  printf 'FAIL weakened not reported\n%s\n' "$RUN_OUT" >&2; failures=$((failures + 1)); }

# ---------- 3. 连不上 -> unknown，非零，且措辞是 WARN 不是 FAIL ----------
FAKE_MODE=offline run --check
# unknown 不判红（离线是常态），但必须出声
check "offline exit 0" 0 "$RUN_RC"
[[ $RUN_OUT == *WARN*linux-good* ]] || {
  printf 'FAIL offline not reported as WARN\n%s\n' "$RUN_OUT" >&2; failures=$((failures + 1)); }
[[ $RUN_OUT != *"FAIL sshd password authentication is ENABLED"* ]] || {
  printf 'FAIL offline must not be reported as weakened\n' >&2; failures=$((failures + 1)); }

# ---------- 4. 输出解不出 -> unknown，不默认成通过 ----------
FAKE_MODE=garbage run --check
check "unparsable exit 0" 0 "$RUN_RC"
[[ $RUN_OUT == *WARN* ]] || { printf 'FAIL unparsable must still warn\n' >&2; failures=$((failures + 1)); }

# ---------- 4b. 已记录的放开：不判红，但必须出声 ----------
run --check linux-known
[ "$RUN_RC" -eq 0 ] || { printf 'FAIL known exception must not fail the check\n' >&2; failures=$((failures + 1)); }
[[ $RUN_OUT == *"linux-known"* ]] || { printf 'FAIL known exception must still be reported\n' >&2; failures=$((failures + 1)); }
[[ $RUN_OUT == *"recorded exception"* ]] || { printf 'FAIL known exception wording missing\n' >&2; failures=$((failures + 1)); }

# ---------- 4c. 不能吃掉外层循环的标准输入 ----------
# 曾经漏了 `</dev/null`：ssh 读走 `while read ... done <plan` 的输入，
# 表现为只检查了前几台就报 checked=N（不是报错，是最难发现的那种）。
FAKE_STEAL_STDIN=1 run
# 假 dev-host 会在每次 exec 时吃掉一行 plan；正常的实现不会。
[[ $RUN_OUT == *"checked=4"* ]] || {
  printf 'FAIL probe consumed loop stdin (expect checked=4)\n%s\n' "$RUN_OUT" >&2; failures=$((failures + 1)); }

# ---------- 4d. Windows 的默认值必须读成 yes，不是 unknown ----------
# Windows OpenSSH 出厂 sshd_config 全是注释行；"没有显式行" = 走默认 = yes。
# 曾把它读成 unknown，等于把一个真问题静默成了"看不见"。
FAKE_MODE=weakened run --check win-box
[[ $RUN_OUT == *"FAIL sshd password authentication is ENABLED on win-box"* ]] || {
  printf 'FAIL windows default not treated as enabled\n%s\n' "$RUN_OUT" >&2; failures=$((failures + 1)); }

# ---------- 5. json 形状 ----------
run --json
case $RUN_OUT in
  *'"hosts":['*'"verdict":"ok"'*) ;;
  *) printf 'FAIL json shape unexpected\n%s\n' "$RUN_OUT" >&2; failures=$((failures + 1)) ;;
esac

# ---------- 6. 指定单一目标只查它 ----------
FAKE_MODE=ok run linux-good
[[ $RUN_OUT != *win-box* ]] || {
  printf 'FAIL explicit target should limit scope\n%s\n' "$RUN_OUT" >&2; failures=$((failures + 1)); }

# ---------- 7. 未登记的显式目标 -> 声明问题（65） ----------
RUN_RC=0
RUN_OUT=$("$tool" no-such-host 2>&1) || RUN_RC=$?
check "unknown target exit 65" 65 "$RUN_RC"

# ---------- 8. registry 不可读 -> 65，不是"全部通过" ----------
DEV_HOST_REGISTRY=$tmp/missing.toml run --check
check "missing registry exit 65" 65 "$RUN_RC"

# ---------- 9. dev-host 缺失 -> 65 ----------
DEV_HOST_AUTH_SSH_TOOL=$tmp/no-such-tool run --check
check "missing dev-host exit 65" 65 "$RUN_RC"

if [ "$failures" -ne 0 ]; then
  printf '%d failure(s)\n' "$failures" >&2
  exit 1
fi
printf 'all dev-host-auth-audit tests passed\n'
