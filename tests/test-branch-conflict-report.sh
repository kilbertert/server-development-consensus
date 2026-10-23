#!/bin/sh
# 「两个已提交分支改同一文件」的报告器。
#
# 与 guard-overlap 不是同一个问题：那条看的是「我的提交 vs 别人**未提交**的改动」，
# 这条看的是「我的提交 vs 别人**已推送**的分支」。实测 2026-10-23：10 个活跃分支里
# 排除冻结/生成文件后仍有 5 对共享文件。
#
# 判据的关键是**比各自相对自己 fork 点的改动**，而不是比两个分支头。两句话几乎一样，
# 结果完全不同：分支头带着各自与 main 之间无关的漂移，直接比会把「只有
# tests/conftest.py 一个文件」的分支报成五处冲突。
set -eu

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tool=$base_dir/bin/dev-worktree
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT
export HOME=$tmp/home
export GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT \
  GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
mkdir -p "$HOME/.local/lib/server-development-consensus" "$HOME/.local/bin"
cp "$base_dir/lib/dev-git-common.sh" "$HOME/.local/lib/server-development-consensus/dev-git-common.sh"
git config --global init.defaultBranch main

fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

repo=$tmp/repo
git init --initial-branch=main "$repo" >/dev/null
cd "$repo"
git config user.name test
git config user.email test@example.com
git config core.hooksPath /dev/null
printf 'shared\n' > shared.txt
printf 'other\n' > other.txt
git add .
git commit -m "chore: initial" >/dev/null

# Two branches that both edit shared.txt → must be reported.
git switch -c feat/a >/dev/null
printf 'a\n' >> shared.txt
git commit -am "feat: a" >/dev/null
git push -q "$repo" feat/a:refs/remotes/origin/feat/a 2>/dev/null || {
  git update-ref refs/remotes/origin/feat/a "$(git rev-parse feat/a)"
}
git update-ref refs/remotes/origin/main "$(git rev-parse main)"

git switch main >/dev/null
git switch -c feat/b >/dev/null
printf 'b\n' >> shared.txt
git commit -am "feat: b" >/dev/null
git update-ref refs/remotes/origin/feat/b "$(git rev-parse feat/b)"

out=$("$tool" report-branch-conflicts --tip feat/a --default origin/main 2>&1) && status=0 || status=$?
[ "$status" -eq 4 ] || fail "overlapping branches were not reported (status=$status): $out"
printf '%s\n' "$out" | grep -q 'other=feat/b' || fail "the overlapping branch is not named: $out"
printf '%s\n' "$out" | grep -q 'path=shared.txt' || fail "the overlapping path is not named: $out"

# A branch that touches a different file must NOT be reported.
git switch main >/dev/null
git switch -c feat/c >/dev/null
printf 'c\n' >> other.txt
git commit -am "feat: c" >/dev/null
git update-ref refs/remotes/origin/feat/c "$(git rev-parse feat/c)"

out=$("$tool" report-branch-conflicts --tip feat/c --default origin/main 2>&1) && status=0 || status=$?
[ "$status" -eq 0 ] || fail "a branch touching an unrelated file was reported (status=$status): $out"
[ -z "$out" ] || fail "a branch touching an unrelated file produced output: $out"

# The remote's own name (`origin/HEAD` abbreviates to `origin`) must not be
# treated as a branch: comparing it reported a conflict with a branch named
# "origin".
git update-ref refs/remotes/origin/HEAD "$(git rev-parse main)"
out=$("$tool" report-branch-conflicts --tip feat/a --default origin/main 2>&1) || true
printf '%s\n' "$out" | grep -q 'other=origin ' && fail "origin/HEAD was reported as a branch"

# 比「各自相对 fork 点的改动」而不是「比两个分支头」——这两句几乎一样，结果完全不同。
#
# 构造：main 在分叉之后前进了一次（改了 shared.txt），feat/d 只改 other.txt。
# 若按分支头比，feat/d 会与「任何触碰 shared.txt 的分支」被报成重叠，而它其实
# 一个共享文件都没碰。这正是 fix/lock-in-conftest 实测报出五处冲突的原因。
git switch main >/dev/null
printf 'main-advance\n' >> shared.txt
git commit -am "chore: main advances" >/dev/null
git update-ref refs/remotes/origin/main "$(git rev-parse main)"

git switch -c feat/d >/dev/null
# A file nobody else touches, so the only plausible reason to report it is the
# wrong comparison basis.
printf 'd\n' >> only-d.txt
git add only-d.txt
git commit -m "feat: d" >/dev/null
git update-ref refs/remotes/origin/feat/d "$(git rev-parse feat/d)"

out=$("$tool" report-branch-conflicts --tip feat/d --default origin/main 2>&1) && status=0 || status=$?
[ "$status" -eq 0 ] || fail "a branch was compared against branch tips instead of its own change (status=$status): $out"

# 推送的是哪个分支必须由调用方给，不能猜。
#
# `for-each-ref --points-at <sha>` 会列出指向该对象的所有 ref——两个本地分支共用一个
# tip 时就有多个，取第一个是任意选择，随后的同名排除会压掉**另一个**分支的真实冲突。
# 评审用「在 feat/a 的 tip 上加一个 feat/0，再让 origin/feat/0 指向冲突的 feat/b」
# 复现了它：报表漏掉 feat/0，同时仍把 feat/a 报成与自己冲突。
git branch feat/0 feat/a
git update-ref refs/remotes/origin/feat/0 "$(git rev-parse feat/b)"

sha=$(git rev-parse feat/a)
out=$("$tool" report-branch-conflicts --tip "$sha" --branch feat/a --default origin/main 2>&1) && status=0 || status=$?
printf '%s\n' "$out" | grep -q 'other=feat/a' && fail "reported a conflict against the pushed branch itself"
printf '%s\n' "$out" | grep -q 'other=feat/0 path=shared.txt' ||
  fail "the other branch sharing the same tip was suppressed: $out"

printf 'branch conflict report passed\n'

# 已知盲区（如实记录，不假装覆盖）：把 `ref_base`（对方 fork 点）换成
# `default_ref`（当前 main）**不会**让上面任何一条转红。差别只在「main 在对方分叉
# 之后前进过，且前进的内容与双方都无关」时才显现。构造那个时序需要 main 前进 →
# 老分支 → 另一个老分支三者交错，本 fixture 没铺到；实测中它正是
# `fix/lock-in-conftest` 报出五处假冲突的原因。

# 报告**不阻断** push —— 这是设计承诺，不是实现细节。
#
# 阻断需要一个操作者还没给出的次序：被挡下的那个人无法自己解决它。而一句
# 「你会和 feat/x 在 docs/y.md 上撞」是他能解决的。
# Extract the report block into a file rather than a process substitution: this
# script is /bin/sh, which has no `<(...)`.
# The range ends at the `esac` that closes the report's case, not at a later
# `exit 1` belonging to the chained-hook validation that follows it.
sed -n '/report-branch-conflicts/,/^esac/p' "$base_dir/git-hooks/pre-push" >"$tmp/report-block"
if grep -q 'exit 1' "$tmp/report-block"; then
  fail 'the branch conflict report exits 1 — it must report, not block'
fi
grep -q 'push continues' "$base_dir/git-hooks/pre-push" ||
  fail 'pre-push does not say the report is non-blocking when it cannot run'
