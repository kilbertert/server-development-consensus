#!/bin/sh
# dev-pr-review: the reply-before-resolve precondition is the safety property,
# so the central assertion here is "the mutation was never sent".
set -eu

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT
export HOME=$tmp/home
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
mkdir -p "$HOME/.local/bin" "$tmp/bin"
cp "$base_dir/bin/dev-pr-review" "$HOME/.local/bin/dev-pr-review"
chmod +x "$HOME/.local/bin/dev-pr-review"
tool=$HOME/.local/bin/dev-pr-review

export GH_CALLS=$tmp/gh.calls
# Mutations are recorded separately from raw argv: the GraphQL query text is
# passed as an argument, so the constants `resolveReviewThread` and
# `addPullRequestReviewThreadReply` appear in every logged query and a grep over
# the argv log cannot tell a sent mutation from a fetched thread list.
export GH_MUTATIONS=$tmp/gh.mutations
export GH_THREADS=$tmp/threads.json
: >"$GH_CALLS"
: >"$GH_MUTATIONS"

# A thread carries findings from the bot only ("PRRT_a"), the bot plus a reply
# from the authenticated account ("PRRT_b"), and an already-resolved thread
# ("PRRT_c"). PRRT_a is the case the precondition exists for: a bot comment is
# not a disposition, so it must never satisfy the gate.
cat >"$tmp/threads.default.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
  {"id":"PRRT_a","isResolved":false,"isOutdated":false,"path":"install.sh","line":10,
   "comments":{"nodes":[{"author":{"login":"devin-ai-integration"},"body":"finding A"}]}},
  {"id":"PRRT_b","isResolved":false,"isOutdated":false,"path":"bin/x","line":20,
   "comments":{"nodes":[{"author":{"login":"devin-ai-integration"},"body":"finding B"},
                        {"author":{"login":"kilbertert"},"body":"fixed in abc1234"}]}},
  {"id":"PRRT_c","isResolved":true,"isOutdated":false,"path":"README.md","line":3,
   "comments":{"nodes":[{"author":{"login":"kilbertert"},"body":"done"}]}}
]}}}}}
JSON

cat >"$tmp/threads.answered.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
  {"id":"PRRT_b","isResolved":false,"isOutdated":false,"path":"bin/x","line":20,
   "comments":{"nodes":[{"author":{"login":"devin-ai-integration"},"body":"finding B"},
                        {"author":{"login":"kilbertert"},"body":"accepted risk: see ADR 4"}]}},
  {"id":"PRRT_c","isResolved":true,"isOutdated":false,"path":"README.md","line":3,
   "comments":{"nodes":[{"author":{"login":"kilbertert"},"body":"done"}]}}
]}}}}}
JSON

cat >"$tmp/threads.none.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[
  {"id":"PRRT_c","isResolved":true,"isOutdated":false,"path":"README.md","line":3,
   "comments":{"nodes":[{"author":{"login":"kilbertert"},"body":"done"}]}}
]}}}}}
JSON

cp "$tmp/threads.default.json" "$GH_THREADS"

cat >"$tmp/bin/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$GH_CALLS"
case "$1" in
  api)
    case "$2" in
      user) printf '%s\n' 'kilbertert' ;;
      graphql)
        for arg in "$@"; do
          case "$arg" in
            *resolveReviewThread*)
              printf 'resolveReviewThread %s\n' "$*" >>"$GH_MUTATIONS"
              printf '%s\n' '{"data":{"resolveReviewThread":{"thread":{"id":"x","isResolved":true}}}}'
              exit 0 ;;
            *addPullRequestReviewThreadReply*)
              printf 'addPullRequestReviewThreadReply %s\n' "$*" >>"$GH_MUTATIONS"
              printf '%s\n' '{"data":{"addPullRequestReviewThreadReply":{"comment":{"id":"c1"}}}}'
              exit 0 ;;
          esac
        done
        cat "$GH_THREADS"
        ;;
      *) exit 2 ;;
    esac
    ;;
  repo) printf '%s\n' 'owner/repo' ;;
  pr)
    case "$2" in
      view) printf '%s\n' '42' ;;
      comment) ;;
      *) exit 2 ;;
    esac
    ;;
  *) exit 2 ;;
esac
STUB
chmod +x "$tmp/bin/gh"
PATH=$tmp/bin:$PATH
export PATH

git init --initial-branch=main "$tmp/repo" >/dev/null
run() { ( cd "$tmp/repo" && "$@" ); }
reset_calls() { : >"$GH_CALLS"; : >"$GH_MUTATIONS"; }
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }
assert_no_call() {
  if grep -q "$1" "$GH_CALLS"; then fail "$2"; fi
}
# The mutation log, not the argv log: the query text is an argument, so grepping
# the argv log for a mutation name matches the thread-list fetch too.
assert_no_mutation() {
  if grep -q "$1" "$GH_MUTATIONS"; then fail "$2"; fi
}
# Run a command inside the fixture checkout and require the documented exit code.
assert_exit_code() {
  want=$1
  shift
  rc=0
  run "$@" >"$tmp/refused.out" 2>&1 || rc=$?
  [ "$rc" -eq "$want" ] || fail "expected exit $want, got $rc"
}
assert_refused_77() { assert_exit_code 77 "$@"; }

# T1 — status lists only unresolved threads and marks who replied.
reset_calls
out=$(run "$tool" status) || fail 'status exited non-zero'
printf '%s\n' "$out" | grep -q 'PRRT_a' || fail 'status omitted the unanswered thread'
printf '%s\n' "$out" | grep -q 'PRRT_b' || fail 'status omitted the answered thread'
if printf '%s\n' "$out" | grep -q 'PRRT_c'; then fail 'status listed a resolved thread'; fi
printf '%s\n' "$out" | grep -q 'UNANSWERED' || fail 'status did not mark the unanswered thread'

# T2 — --json carries the same fact machine-readably.
run "$tool" status --json | grep -q '"answeredByYou": false' ||
  fail 'status --json lost the answered flag'

# T3 — no unresolved threads: a clean, empty run.
out=$(GH_THREADS=$tmp/threads.none.json run "$tool" status) || fail 'empty status exited non-zero'
printf '%s\n' "$out" | grep -q 'no unresolved review threads' ||
  fail 'status did not report the empty state'

# T4 — the precondition: a bot-only thread cannot be resolved, and no mutation is sent.
reset_calls
if GH_THREADS=$tmp/threads.default.json run "$tool" resolve PRRT_a >"$tmp/t4.out" 2>&1; then
  fail 'resolve accepted a thread with no reply from the authenticated account'
fi
assert_refused_77 "$tool" resolve PRRT_a
assert_no_mutation 'resolveReviewThread' 'resolve sent the mutation despite the missing reply'
grep -q 'has no reply' "$tmp/t4.out" || fail 'resolve did not explain the refusal'

# T5 — an answered thread resolves, and the mutation names it.
reset_calls
GH_THREADS=$tmp/threads.answered.json run "$tool" resolve PRRT_b >/dev/null ||
  fail 'resolve failed on an answered thread'
grep -q 'resolveReviewThread' "$GH_MUTATIONS" || fail 'resolve did not send the mutation'
grep -q 'id=PRRT_b' "$GH_MUTATIONS" || fail 'resolve sent the mutation for the wrong thread'

# T6 — an already-resolved thread is an idempotent no-op.
reset_calls
out=$(GH_THREADS=$tmp/threads.none.json run "$tool" resolve PRRT_c) ||
  fail 'resolve exited non-zero on a resolved thread'
printf '%s\n' "$out" | grep -q 'already resolved' || fail 'resolve did not report the no-op'
assert_no_mutation 'resolveReviewThread' 'resolve re-sent a mutation for a resolved thread'

# T7 — reply posts in-thread, and an empty reply is refused (the reply is the record).
reset_calls
run "$tool" reply PRRT_a --body 'not applicable: covered by the port registry rule' >/dev/null ||
  fail 'reply failed'
grep -q 'addPullRequestReviewThreadReply' "$GH_MUTATIONS" || fail 'reply did not post the comment'
reset_calls
assert_refused_77 "$tool" reply PRRT_a --body '   '
assert_no_mutation 'addPullRequestReviewThreadReply' 'reply posted an empty body'

# T8 — close-loop refuses while a thread is unanswered, and posts nothing.
reset_calls
if GH_THREADS=$tmp/threads.default.json run "$tool" close-loop >"$tmp/t8.out" 2>&1; then
  fail 'close-loop closed a loop with an unanswered thread'
fi
assert_refused_77 "$tool" close-loop
assert_no_call '/devin review' 'close-loop requested a re-review with a thread unanswered'
assert_no_call 'pr comment' 'close-loop commented with a thread unanswered'
assert_no_mutation 'resolveReviewThread' 'close-loop resolved a thread that had no reply'
grep -q 'PRRT_a' "$tmp/t8.out" || fail 'close-loop did not name the unanswered thread'

# T9 — every thread answered: resolve them, then exactly one re-review.
reset_calls
GH_THREADS=$tmp/threads.answered.json run "$tool" close-loop >"$tmp/t9.out" ||
  fail 'close-loop failed with every thread answered'
grep -q 'resolveReviewThread' "$GH_MUTATIONS" || fail 'close-loop did not resolve the answered thread'
[ "$(grep -c '/devin review' "$GH_CALLS")" -eq 1 ] ||
  fail 'close-loop did not post exactly one re-review'

# T10 — nothing unresolved: a no-op that does not spend a review.
reset_calls
GH_THREADS=$tmp/threads.none.json run "$tool" close-loop >"$tmp/t10.out" ||
  fail 'close-loop failed on an empty set'
grep -q 'nothing to close' "$tmp/t10.out" || fail 'close-loop did not report the no-op'
assert_no_call '/devin review' 'close-loop spent a re-review with nothing to close'

# T11 — an externally governed repository is untouched before any network call.
git -C "$tmp/repo" config serverPolicy.repositoryClass external
reset_calls
if run "$tool" close-loop >"$tmp/t11.out" 2>&1; then
  fail 'close-loop ran in an externally governed repository'
fi
if run "$tool" resolve PRRT_b >/dev/null 2>&1; then
  fail 'resolve ran in an externally governed repository'
fi
if run "$tool" reply PRRT_b --body 'fixed in abc1234' >/dev/null 2>&1; then
  fail 'reply ran in an externally governed repository'
fi
[ ! -s "$GH_CALLS" ] || fail 'an externally governed repository reached gh'
git -C "$tmp/repo" config --unset serverPolicy.repositoryClass

# T12 — a missing --body-file is a clean exit, not a traceback.
reset_calls
assert_exit_code 65 "$tool" reply PRRT_a --body-file "$tmp/does-not-exist"
if grep -q 'Traceback' "$tmp/refused.out"; then fail 'a missing body file raised a traceback'; fi

# T13 — usage errors are refused before gh is reached.
reset_calls
assert_exit_code 2 "$tool" resolve
assert_exit_code 2 "$tool" frobnicate
[ ! -s "$GH_CALLS" ] || fail 'a usage error reached gh'

printf '%s\n' 'dev-pr-review tests passed'
