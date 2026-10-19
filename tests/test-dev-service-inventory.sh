#!/usr/bin/env bash
set -Eeuo pipefail

# Tests for dev-service-inventory.
#
# The tool reads live sockets, which would make every assertion depend on what
# happens to be running on the machine. Instead both inputs are injected:
#   DEV_SERVICE_INVENTORY_SS_LISTEN   — the listener table
#   DEV_SERVICE_INVENTORY_SS_LISTENP  — the same table with process owners
# The fixtures below are shaped exactly like real `ss -tlnH` output, which has
# five columns with the local address in the fourth.

trap 'status=$?; printf "FAIL test-dev-service-inventory.sh:%s command=%q status=%s\\n" "$LINENO" "$BASH_COMMAND" "$status" >&2; exit "$status"' ERR

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tool=$base_dir/bin/dev-service-inventory
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

# run_rc <listen-fixture> <listenp-fixture> [mode]
# 把输出写入 $RUN_OUT、退出码写入 $RUN_RC，避免依赖命令替换的返回值
# （命令替换里的非零返回在 `set -e` 下会让整个测试脚本退出）。
run_rc() {
  local listen=$1 listenp=$2 mode=${3:-}
  RUN_RC=0
  RUN_OUT=$(DEV_SERVICE_INVENTORY_SS_LISTEN="cat $listen" \
            DEV_SERVICE_INVENTORY_SS_LISTENP="cat $listenp" \
              "$tool" "$mode" 2>&1) || RUN_RC=$?
}

# run <listen-fixture> <listenp-fixture> [mode] — 只要输出
run() {
  RUN_RC=
  run_rc "$@"
  printf '%s' "$RUN_OUT"
}

# --- 夹具 -------------------------------------------------------------------
# 正常情形：平台入口 + 一个业务违规 + 一个环回（应被忽略）+ 一个网络平面
cat >"$tmp/listen" <<'EOF'
LISTEN 0 511 0.0.0.0:22 0.0.0.0:*
LISTEN 0 511 0.0.0.0:443 0.0.0.0:*
LISTEN 0 511 0.0.0.0:9000 0.0.0.0:*
LISTEN 0 511 127.0.0.1:5432 0.0.0.0:*
LISTEN 0 511 100.64.0.5%tailscale0:41641 0.0.0.0:*
EOF
cat >"$tmp/listenp" <<'EOF'
LISTEN 0 511 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=1,fd=3))
LISTEN 0 511 0.0.0.0:443 0.0.0.0:* users:(("nginx",pid=2,fd=3))
LISTEN 0 511 0.0.0.0:9000 0.0.0.0:* users:(("myapp",pid=3,fd=3))
LISTEN 0 511 127.0.0.1:5432 0.0.0.0:* users:(("postgres",pid=4,fd=3))
LISTEN 0 511 100.64.0.5%tailscale0:41641 0.0.0.0:* users:(("tailscaled",pid=5,fd=3))
EOF

cat >"$tmp/plane" <<'EOF'
LISTEN 0 511 100.64.0.5:41641 0.0.0.0:* users:(("tailscaled",pid=5,fd=3))
EOF
cat >"$tmp/plane-listen" <<'EOF'
LISTEN 0 511 100.64.0.5:41641 0.0.0.0:*
EOF
: >"$tmp/empty"

# --- 1. 违规识别 -------------------------------------------------------------
out=$(run "$tmp/listen" "$tmp/listenp")
grep -q 'violation.*9000' <<<"$out" && printf 'ok violation detected\n' ||
  { printf 'FAIL violation not detected\n%s\n' "$out" >&2; failures=$((failures + 1)); }

# --- 2. 平台入口不算违规 -----------------------------------------------------
grep -q 'platform.*22' <<<"$out" && printf 'ok platform port allowed\n' ||
  { printf 'FAIL platform port flagged\n%s\n' "$out" >&2; failures=$((failures + 1)); }

# --- 3. 环回不算违规 ---------------------------------------------------------
if grep -q '5432' <<<"$out"; then
  printf 'FAIL loopback listener reported\n%s\n' "$out" >&2
  failures=$((failures + 1))
else
  printf 'ok loopback ignored\n'
fi

# --- 4. 网络平面不算业务违规 -------------------------------------------------
out=$(run "$tmp/plane-listen" "$tmp/plane")
grep -q 'plane' <<<"$out" && printf 'ok network plane skipped\n' ||
  { printf 'FAIL network plane not recognised\n%s\n' "$out" >&2; failures=$((failures + 1)); }

# --- 5. --check：有违规即非零退出 --------------------------------------------
run_rc "$tmp/listen" "$tmp/listenp" --check
check "--check exits non-zero on violation" "1" "$RUN_RC"

# --- 6. --check：无违规即零退出 ----------------------------------------------
run_rc "$tmp/empty" "$tmp/empty" --check
check "--check exits zero on clean host" "0" "$RUN_RC"

# --- 7. --check 安静：只报违规行，不打印整张表 --------------------------------
run_rc "$tmp/listen" "$tmp/listenp" --check
out=$RUN_OUT
if grep -q 'VERDICT' <<<"$out"; then
  printf 'FAIL --check printed the whole table\n' >&2
  failures=$((failures + 1))
else
  printf 'ok --check stays quiet\n'
fi
grep -q '9000' <<<"$out" && printf 'ok --check names the offender\n' ||
  { printf 'FAIL --check did not name the port\n%s\n' "$out" >&2; failures=$((failures + 1)); }

# --- 8. --json 是合法 JSON ---------------------------------------------------
out=$(run "$tmp/listen" "$tmp/listenp" --json)
python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["violations"]==1' "$out" \
  && printf 'ok json shape\n' ||
  { printf 'FAIL json invalid\n%s\n' "$out" >&2; failures=$((failures + 1)); }

# --- 9. 归因缺失时标 unknown，而不是当成安全 ---------------------------------
out=$(run "$tmp/listen" "$tmp/empty")
grep -q 'unknown' <<<"$out" && printf 'ok unattributed marked unknown\n' ||
  { printf 'FAIL unattributed listeners looked safe\n%s\n' "$out" >&2; failures=$((failures + 1)); }

# --- 10. 已评估例外：可见但不阻塞 ---------------------------------------------
# 例外表在生产上是**空的**（开发机已无任何非环回业务监听），所以夹具不能绑死
# 某条真实条目 —— 那会让这些测试在债务还清后失效，而它们验证的是**机制**。
# 用测试缝注入一条临时例外。
INJECT=9999/test-app
cat >"$tmp/acc-listen" <<'EOF'
LISTEN 0 511 0.0.0.0:9999 0.0.0.0:*
EOF
cat >"$tmp/acc-listenp" <<'EOF'
LISTEN 0 511 0.0.0.0:9999 0.0.0.0:* users:(("test-app",pid=9,fd=3))
EOF
RUN_RC=0
RUN_OUT=$(DEV_SERVICE_INVENTORY_ACCEPTED="$INJECT" \
          DEV_SERVICE_INVENTORY_SS_LISTEN="cat $tmp/acc-listen" \
          DEV_SERVICE_INVENTORY_SS_LISTENP="cat $tmp/acc-listenp" \
            "$tool" --check 2>&1) || RUN_RC=$?
check "accepted residual does not fail check" "0" "$RUN_RC"
RUN_OUT=$(DEV_SERVICE_INVENTORY_ACCEPTED="$INJECT" \
          DEV_SERVICE_INVENTORY_SS_LISTEN="cat $tmp/acc-listen" \
          DEV_SERVICE_INVENTORY_SS_LISTENP="cat $tmp/acc-listenp" \
            "$tool" 2>&1)
grep -q 'accepted.*9999' <<<"$RUN_OUT" && printf 'ok accepted residual is visible\n' ||
  { printf 'FAIL accepted residual hidden\n%s\n' "$RUN_OUT" >&2; failures=$((failures + 1)); }

# --- 11. 例外不能变成后门：同端口不同程序仍是违规 ------------------------------
# 这是关键判据 —— 例外绑定的是 port+owner，换了程序就必须失效。
cat >"$tmp/acc-other" <<'EOF'
LISTEN 0 511 0.0.0.0:9999 0.0.0.0:* users:(("some-other-service",pid=10,fd=3))
EOF
RUN_RC=0
RUN_OUT=$(DEV_SERVICE_INVENTORY_ACCEPTED="$INJECT" \
          DEV_SERVICE_INVENTORY_SS_LISTEN="cat $tmp/acc-listen" \
          DEV_SERVICE_INVENTORY_SS_LISTENP="cat $tmp/acc-other" \
            "$tool" --check 2>&1) || RUN_RC=$?
check "same port, different owner still violates" "1" "$RUN_RC"


# --- 12. 无特权归因：只有 cgroup 字段也能认出归属 --------------------------
# 真实场景（2026-10-19）：root 的 tailscaled 不给 users:()，只给 cgroup。
# 审计 unit 带 NoNewPrivileges=true，sudo 不可用，因此这条路是唯一的归因方式。
# 用当前用户自己的一个 unit 造夹具不现实，这里直接验证解析函数本身：
# 给一行只含 cgroup 的输入，期望 owner 是 unit 名去掉 .service 后缀。
cat >"$tmp/nodecode-listen" <<'EOF'
LISTEN 0 511 0.0.0.0:9401 0.0.0.0:*
EOF
cat >"$tmp/cgroup" <<'EOF'
LISTEN 0 511 0.0.0.0:9401 0.0.0.0:* ino:1 sk:1 cgroup:/system.slice/some-daemon.service <-> 
EOF
run_rc "$tmp/nodecode-listen" "$tmp/cgroup" --check
out=$RUN_OUT
grep -q 'owner=some-daemon' <<<"$out" && printf 'ok cgroup-only attribution resolved\n' ||
  { printf 'FAIL cgroup-only attribution not resolved\n%s\n' "$out" >&2; failures=$((failures + 1)); }

# --- 13. 裸 sk:0（无 AF_NETLINK 时的退化形态）必须仍是 unknown --------------
cat >"$tmp/degraded" <<'EOF'
LISTEN 0 511 0.0.0.0:9402 0.0.0.0:* ino:2 sk:0 
EOF
cat >"$tmp/degraded-listen" <<'EOF'
LISTEN 0 511 0.0.0.0:9402 0.0.0.0:*
EOF
out=$(run "$tmp/degraded-listen" "$tmp/degraded")
grep -q 'unknown' <<<"$out" && printf 'ok degraded attribution stays unknown\n' ||
  { printf 'FAIL degraded attribution looked resolved\n%s\n' "$out" >&2; failures=$((failures + 1)); }

# --- 14. 归属必须按整列匹配地址，不能被别的字段里的数字骗到 ---------------
# 真实事故（2026-10-19）：`grep -F ":22 "` 命中了 `sk:22` 所在的 2281 那一行，
# 于是 0.0.0.0:22 的归属被读成 dockerd。同端口不同地址必须各归各位。
cat >"$tmp/multi-listen" <<'EOF'
LISTEN 0 4096 0.0.0.0:22 0.0.0.0:*
LISTEN 0 4096 0.0.0.0:2281 0.0.0.0:*
EOF
cat >"$tmp/multi-listenp" <<'EOF'
LISTEN 0 4096 0.0.0.0:22 0.0.0.0:* ino:1 sk:400d cgroup:/system.slice/ssh.service <-> 
LISTEN 0 4096 0.0.0.0:2281 0.0.0.0:* ino:2 sk:22 cgroup:/system.slice/docker.service <-> 
EOF
out=$(run "$tmp/multi-listen" "$tmp/multi-listenp")
grep -qE 'platform +22 +0\.0\.0\.0:22 +ssh' <<<"$out" && printf 'ok exact address match wins\n' ||
  { printf 'FAIL port 22 attributed to the wrong listener\n%s\n' "$out" >&2; failures=$((failures + 1)); }

# --- 15. socket-activated 的 unit 也能归因 ----------------------------------
# ssh.socket 没有 MainPID；不识别 .socket 会让 sshd 退化成 unknown。
cat >"$tmp/sock-listen" <<'EOF'
LISTEN 0 4096 0.0.0.0:9403 0.0.0.0:*
EOF
cat >"$tmp/sock-listenp" <<'EOF'
LISTEN 0 4096 0.0.0.0:9403 0.0.0.0:* ino:3 sk:3 cgroup:/system.slice/some-svc.socket <-> 
EOF
out=$(run "$tmp/sock-listen" "$tmp/sock-listenp")
grep -qE 'violation +9403 +0\.0\.0\.0:9403 +some-svc' <<<"$out" && printf 'ok socket unit attributed\n' ||
  { printf 'FAIL socket unit not attributed\n%s\n' "$out" >&2; failures=$((failures + 1)); }

# --- 16. 绑在覆盖网地址上不算对外服务 ---------------------------------------
# 判据必须是地址，不是程序名：同一个 frps 绑 0.0.0.0 违规、绑 tailnet 地址
# 只是开发平面内部通信。这样既不用维护程序白名单，也不会放宽判据。
cat >"$tmp/overlay-listen" <<'EOF'
LISTEN 0 4096 100.96.121.55:7000 0.0.0.0:*
LISTEN 0 4096 [fd7a:115c:a1e0::1438:b619]:52420 [::]:*
EOF
cat >"$tmp/overlay-listenp" <<'EOF'
LISTEN 0 4096 100.96.121.55:7000 0.0.0.0:* ino:1 sk:1 cgroup:/user.slice/user-1000.slice/user@1000.service/app.slice/frps.service <-> 
LISTEN 0 4096 [fd7a:115c:a1e0::1438:b619]:52420 [::]:* ino:2 sk:2 cgroup:/system.slice/tailscaled.service <-> 
EOF
run_rc "$tmp/overlay-listen" "$tmp/overlay-listenp" --check
check "overlay-address binds are not violations" "0" "$RUN_RC"

# --- 17. 同一个程序绑 0.0.0.0 仍然违规 --------------------------------------
# 这条保证上一条不是"给 frps 开后门"：放宽的是地址，不是程序。
cat >"$tmp/wildcard-listen" <<'EOF'
LISTEN 0 4096 0.0.0.0:7000 0.0.0.0:*
EOF
cat >"$tmp/wildcard-listenp" <<'EOF'
LISTEN 0 4096 0.0.0.0:7000 0.0.0.0:* ino:3 sk:3 cgroup:/user.slice/user-1000.slice/user@1000.service/app.slice/frps.service <-> 
EOF
run_rc "$tmp/wildcard-listen" "$tmp/wildcard-listenp" --check
check "same program on 0.0.0.0 still violates" "1" "$RUN_RC"

# --- 10. 未知参数应拒绝 -------------------------------------------------------
"$tool" --bogus >/dev/null 2>&1 && status=0 || status=$?
check "unknown flag rejected" "64" "$status"

# --- 11. 已退役的例外必须不再生效 ---------------------------------------------
# `27641/api`（blog-chat 的 Go 二进制）曾在 ACCEPTED_RESIDUALS 里。服务迁往
# service host 后开发机上已无该监听，键随之失效并被删除。这条断言防它被顺手加回：
# 开发机上若真的出现 27641，必须是 violation，而不是一个"早就批过"的 accepted。
cat >"$tmp/retired-listen" <<'EOF'
LISTEN 0 4096 *:27641 *:*
EOF
cat >"$tmp/retired-listenp" <<'EOF'
LISTEN 0 4096 *:27641 *:* users:(("api",pid=11,fd=3))
EOF
run_rc "$tmp/retired-listen" "$tmp/retired-listenp" --check
check "retired 27641 residual no longer exempts" "1" "$RUN_RC"

if [[ $failures -gt 0 ]]; then
  printf 'dev-service-inventory tests failed: %d\n' "$failures" >&2
  exit 1
fi
printf 'dev-service-inventory tests passed\n'
