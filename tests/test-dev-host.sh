#!/usr/bin/env bash
# dev-host 的测试。只断言 CLI 边界的外部行为:退出码、输出、以及对"目标机"的副作用。
#
# 目标机用**假 ssh/scp 替身**表示:
#   - 替身把每次调用记进 $SSH_LOG —— 以"替身是否被调用"作为"目标未被触碰"的判据
#   - 替身模拟 ssh 的主机密钥校验:比对 UserKnownHostsFile 中的键与 $FAKE_REMOTE_KEY
#     不符则照真实 ssh 的行为失败(Host key verification failed, rc 255)
# 因此全部测试不需要任何真实主机或网络。

set -euo pipefail

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export HOME=$tmp/home
export XDG_CONFIG_HOME=$HOME/.config
export DEV_HOST_REGISTRY=$HOME/.config/dev-host/hosts.toml
export SSH_LOG=$tmp/ssh.log
export FAKE_SSH_RC=0
unset DEV_HOST_PROJECT || true

mkdir -p "$HOME/bin" "$HOME/.config/dev-host" "$tmp/proj"
: >"$SSH_LOG"

# 一对真实的密钥,用作"已登记的主机公钥"
ssh-keygen -t ed25519 -f "$tmp/hostkey" -N '' -q
REGISTERED_KEY=$(cat "$tmp/hostkey.pub")
OTHER_KEY=$(ssh-keygen -t ed25519 -f "$tmp/other" -N '' -q && cat "$tmp/other.pub")
export FAKE_REMOTE_KEY=$REGISTERED_KEY

# ---------- 假 ssh ----------
cat >"$HOME/bin/ssh" <<'FAKE'
#!/bin/sh
# -G:模拟 ssh -G 的配置查询(dev-host 用它取地址/端口,不记录为一次访问)
if [ "${1:-}" = "-G" ]; then
  printf 'hostname 127.0.0.1\nport 22\n'
  exit 0
fi

known=""
argv=""
while [ $# -gt 0 ]; do
  case $1 in
    -o)
      case ${2:-} in
        UserKnownHostsFile=*) known=${2#UserKnownHostsFile=} ;;
      esac
      shift 2 ;;
    -*) shift ;;
    *) argv="$argv|$1"; shift ;;
  esac
done
printf 'ssh%s\n' "$argv" >>"$SSH_LOG"

# 模拟主机密钥校验(真实 ssh 在这里会拒绝)
if [ -n "$known" ]; then
  if ! grep -qF "$FAKE_REMOTE_KEY" "$known" 2>/dev/null; then
    printf 'Host key verification failed.\n' >&2
    exit 255
  fi
fi

printf 'fake-ssh-output\n'
exit "$FAKE_SSH_RC"
FAKE

cat >"$HOME/bin/scp" <<'FAKE'
#!/bin/sh
argv=""
while [ $# -gt 0 ]; do
  case $1 in
    -o) shift 2 ;;
    -*) shift ;;
    *) argv="$argv|$1"; shift ;;
  esac
done
printf 'scp%s\n' "$argv" >>"$SSH_LOG"
printf 'fake-scp-ok\n'
exit "$FAKE_SSH_RC"
FAKE

chmod +x "$HOME/bin/ssh" "$HOME/bin/scp"
export PATH="$HOME/bin:$PATH"
export DEV_HOST="$base_dir/bin/dev-host"
chmod +x "$DEV_HOST"

# ---------- 声明 ----------
cat >"$DEV_HOST_REGISTRY" <<EOF
[hosts.hc-prod]
ssh_alias = "hc-prod"
role      = "project-production-host"
plane     = "service"
owner     = "internal"
access    = "ssh"
hostkey   = "$REGISTERED_KEY"

[hosts.scratch]
ssh_alias = "scratch"
role      = "development-host"
plane     = "development"
owner     = "internal"
access    = "ssh"
hostkey   = "$REGISTERED_KEY"

[hosts.win-prod]
ssh_alias = "win-prod"
role      = "project-production-host"
plane     = "service"
owner     = "internal"
access    = "rdp"
status    = "exception"
description = "22 端口关闭,仅 RDP 可达"

[hosts.retired-box]
ssh_alias = "retired-box"
role      = "service-host"
plane     = "service"
owner     = "internal"
access    = "ssh"
status    = "retired"
hostkey   = "$REGISTERED_KEY"
EOF
chmod 600 "$DEV_HOST_REGISTRY"

cat >"$tmp/proj/.dev-host.toml" <<'EOF'
[[targets]]
name = "prod"
host = "hc-prod"
[targets.paths]
app  = "/srv/app"
logs = "/srv/app/logs"

[[targets]]
name = "box"
host = "scratch"

[[targets]]
name = "win"
host = "win-prod"

[[targets]]
name = "old"
host = "retired-box"
EOF
export DEV_HOST_PROJECT="$tmp/proj/.dev-host.toml"

# ---------- 断言小工具 ----------
fail=0
ok()   { printf '  ok   %s\n' "$1"; }
bad()  { printf '  FAIL %s\n' "$1"; fail=1; }

rc_is() { # rc_is <期望> <描述> -- <命令...>
  local want=$1 desc=$2; shift 3
  local got=0
  "$@" >"$tmp/out" 2>"$tmp/err" || got=$?
  if [ "$got" -eq "$want" ]; then ok "$desc (rc=$got)"; else
    bad "$desc: 期望 rc=$want,得到 rc=$got"; sed 's/^/       /' "$tmp/err" | head -3; fi
}
untouched() {
  if [ ! -s "$SSH_LOG" ]; then ok "$1: 目标未被触碰"; else
    bad "$1: 目标被触碰了"; sed 's/^/       /' "$SSH_LOG" | head -3; fi
}
touched() {
  if [ -s "$SSH_LOG" ]; then ok "$1: 已到达目标"; else bad "$1: 未到达目标"; fi
  : >"$SSH_LOG"
}
reset_log() { : >"$SSH_LOG"; }

echo "== 安全用例(本次的全部价值)=="

# T1 指纹不符 -> 拒绝执行,且目标未被触碰
#    已登记 RE的ED_KEY,但远端实际是 OTHER_KEY
reset_log
FAKE_REMOTE_KEY=$OTHER_KEY rc_is 255 "T1 指纹不符应失败" -- "$DEV_HOST" read prod /srv/app/logs/x.log
if grep -q 'Host key verification failed' "$tmp/err"; then ok "T1 失败原因是主机密钥校验"; else bad "T1 失败原因不是主机密钥校验"; fi
if grep -q 'fake-ssh-output' "$tmp/out"; then bad "T1 不应产生输出"; else ok "T1 未产生输出(命令没跑)"; fi
export FAKE_REMOTE_KEY=$REGISTERED_KEY

# T2 服务主机写入、无产物身份 -> 拒绝
reset_log
rc_is 77 "T2 服务主机写入无产物身份应拒绝" -- sh -c "printf hi | '$DEV_HOST' write prod /srv/app/f"
grep -q '产物身份' "$tmp/err" && ok "T2 拒绝理由说明了放行条件" || bad "T2 拒绝理由未说明放行条件"
untouched "T2"

# T3 服务主机写入、产物 sha256 不符 -> 拒绝
reset_log
rc_is 77 "T3 产物身份不符应拒绝" -- sh -c "printf hi | '$DEV_HOST' write prod /srv/app/f --artifact-sha256 0000000000000000000000000000000000000000000000000000000000000000"
untouched "T3"

# T4 access=rdp 的目标 -> 拒绝,不尝试连接
reset_log
rc_is 77 "T4 rdp 目标应拒绝" -- "$DEV_HOST" read win /x
grep -q '不覆盖' "$tmp/err" && ok "T4 说明是不可覆盖而非连接失败" || bad "T4 未说明原因"
untouched "T4"

# T4b 已退役目标 -> 拒绝
reset_log
rc_is 77 "T4b 退役目标应拒绝" -- "$DEV_HOST" ls old /x
untouched "T4b"

echo
echo "== 未登记 / 声明不可读 -> fail-closed =="

# T5 未登记主机
reset_log
rc_is 65 "T5 未登记主机应报错" -- "$DEV_HOST" read nonexistent /x
untouched "T5"

# T6 声明文件不可读 -> 视为不存在
reset_log
DEV_HOST_PROJECT="$tmp/proj/.dev-host.toml" \
  sh -c "mv '$DEV_HOST_PROJECT' '$DEV_HOST_PROJECT.hidden'; trap 'mv \"$DEV_HOST_PROJECT.hidden\" \"$DEV_HOST_PROJECT\"' EXIT; '$DEV_HOST' read prod /x" \
  >"$tmp/out" 2>"$tmp/err" && rc=0 || rc=$?
[ "$rc" -eq 65 ] && ok "T6 声明不可读应报错 (rc=65)" || bad "T6 期望 rc=65,得到 rc=$rc"
untouched "T6"

# T7 非 TOML
reset_log
cp "$DEV_HOST_PROJECT" "$tmp/good.toml"
printf 'this is not toml [[[\n' >"$DEV_HOST_PROJECT"
rc_is 65 "T7 声明不可解析应报错" -- "$DEV_HOST" read prod /x
cp "$tmp/good.toml" "$DEV_HOST_PROJECT"
untouched "T7"

echo
echo "== 正常路径 =="

# T8 read 透传输出
reset_log
rc_is 0 "T8 read 成功" -- "$DEV_HOST" read prod /srv/app/logs/x.log
grep -q 'fake-ssh-output' "$tmp/out" && ok "T8 透传了远端输出" || bad "T8 未透传输出"
touched "T8"

# T9 exec 透传远端退出码(核心要求:真实退出码)
reset_log
FAKE_SSH_RC=42 rc_is 42 "T9 exec 透传远端退出码" -- "$DEV_HOST" exec box --allow-service-exec -- true
export FAKE_SSH_RC=0
reset_log

# T9b 开发机 exec 无需开关
rc_is 0 "T9b 开发机 exec 无需开关" -- "$DEV_HOST" exec box -- true
touched "T9b"

# T10 服务主机 exec 默认拒绝,--allow-service-exec 放行
reset_log
rc_is 77 "T10 服务主机 exec 默认拒绝" -- "$DEV_HOST" exec prod -- systemctl status x
untouched "T10"

reset_log
rc_is 0 "T10b 服务主机 exec 显式放行" -- "$DEV_HOST" exec prod --allow-service-exec -- systemctl status x
touched "T10b"

# T11 非服务主机写入放行(不设门槛)
reset_log
rc_is 0 "T11 开发机写入放行" -- sh -c "printf data | '$DEV_HOST' write box /tmp/f"
touched "T11"

# T12 服务主机写入 + 正确的产物身份 -> 放行
reset_log
ART=$(printf 'the-artifact' | sha256sum | awk '{print $1}')
rc_is 0 "T12 服务主机写入带正确产物身份应放行" -- sh -c "printf 'the-artifact' | '$DEV_HOST' write prod /srv/app/f --artifact-sha256 $ART"
touched "T12"

# T13 前置条件 --if-sha256 不符 -> 拒绝(远端 sha 来自假 ssh 输出,不匹配)
reset_log
rc_is 77 "T13 if-sha256 不符应拒绝" -- sh -c "printf x | '$DEV_HOST' write prod /srv/app/f --artifact-sha256 \$(printf x | sha256sum | awk '{print \$1}') --if-sha256 deadbeef"
if grep -q '前置条件失败' "$tmp/err"; then ok "T13 指明是前置条件失败"; else bad "T13 未指明前置条件"; fi

# T14 cp 到服务主机带产物身份 -> 放行;不带 -> 拒绝
reset_log
printf 'artifact-bytes' >"$tmp/art.bin"
A2=$(sha256sum "$tmp/art.bin" | awk '{print $1}')
rc_is 0 "T14 cp 带产物身份放行" -- "$DEV_HOST" cp prod "$tmp/art.bin" --dest /srv/app/art.bin --artifact-sha256 "$A2"
touched "T14"

reset_log
rc_is 77 "T14b cp 不带产物身份拒绝" -- "$DEV_HOST" cp prod "$tmp/art.bin" --dest /srv/app/art.bin
untouched "T14b"

# T15 ls / find
reset_log
rc_is 0 "T15 ls 成功" -- "$DEV_HOST" ls prod /srv/app
touched "T15"
reset_log
rc_is 0 "T15b find 成功" -- "$DEV_HOST" find prod '*.jar' --path /srv/app --newer 1
touched "T15b"

# T16 show 报告写权限,不触碰目标
reset_log
rc_is 0 "T16 show prod 成功" -- "$DEV_HOST" show prod
grep -q '^writable    no' "$tmp/out" && ok "T16 正确报告不可写" || bad "T16 writable 报告错误"
untouched "T16"
reset_log
rc_is 0 "T16b show box 成功" -- "$DEV_HOST" show box
grep -q '^writable    yes' "$tmp/out" && ok "T16b 正确报告可写" || bad "T16b writable 报告错误"
untouched "T16b"

# T17 hosts 列出清单
reset_log
rc_is 0 "T17 hosts 列出清单" -- "$DEV_HOST" hosts
grep -q 'hc-prod' "$tmp/out" && ok "T17 含已登记主机" || bad "T17 清单缺失"
untouched "T17"

# T18 超时 -> 124(用真实 timeout + 真 sleep 的假 ssh 模拟不响应)
# 没有 timeout 时 dev-host 会退化为不设超时,故本用例跳过而非误判失败
if ! command -v timeout >/dev/null 2>&1; then
  echo "  skip T18(环境无 timeout)"
else
reset_log
cat >"$HOME/bin/ssh" <<'SLOW'
#!/bin/sh
[ "${1:-}" = "-G" ] && { printf 'hostname 127.0.0.1\nport 22\n'; exit 0; }
sleep 30
SLOW
chmod +x "$HOME/bin/ssh"
rc_is 124 "T18 超时应报 124" -- "$DEV_HOST" exec box --timeout 1 -- sleep 30
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "全部通过"
else
  echo "有失败用例" >&2
  exit 1
fi
