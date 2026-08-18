#!/bin/sh
set -eu

base_dir=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

HOME="$tmp/home" REVIEW_SENTINEL_INSTALL_TESTING=1 "$base_dir/install.sh" >"$tmp/output" 2>&1 || true
grep -q 'review-sentinel installed but inactive' "$tmp/output"
[ -f "$tmp/home/.config/review-sentinel/review-sentinel.env" ]
[ "$(stat -c '%a' "$tmp/home/.config/review-sentinel/review-sentinel.env")" = 600 ]
[ "$(stat -c '%a' "$tmp/home/.config/systemd/user/review-sentinel.service")" = 600 ]
[ -f "$tmp/home/.local/lib/review-sentinel/review_sentinel/cli.py" ]
[ -f "$tmp/home/.local/share/review-sentinel/schema.json" ]

printf '%s\n' 'review-sentinel installer tests passed'
