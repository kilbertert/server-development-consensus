#!/bin/sh
set -eu

if [ "${REVIEW_SENTINEL_INSTALL_TESTING:-}" != 1 ] && {
  [ "$(id -un)" != claude ] || [ "${HOME:-}" != /home/claude ]
}; then
  printf '%s\n' 'error: review-sentinel installer must run as claude with HOME=/home/claude' >&2
  exit 1
fi

base_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
python_bin=${REVIEW_SENTINEL_PYTHON:-/home/claude/miniconda3/bin/python3}
[ -x "$python_bin" ] || python_bin=/usr/bin/python3
install -d -m 700 "$HOME/.config/review-sentinel" "$HOME/.local/lib/review-sentinel/review_sentinel" \
  "$HOME/.local/share/review-sentinel" "$HOME/.local/state/review-sentinel"
cp -a "$base_dir/review_sentinel/." "$HOME/.local/lib/review-sentinel/review_sentinel/"
install -m 600 "$base_dir/review_sentinel/schema.json" "$HOME/.local/share/review-sentinel/schema.json"
if [ ! -e "$HOME/.config/review-sentinel/review-sentinel.env" ]; then
  install -m 600 "$base_dir/review-sentinel.env.example" \
    "$HOME/.config/review-sentinel/review-sentinel.env"
fi
install -d -m 700 "$HOME/.config/systemd/user"
install -m 600 "$base_dir/systemd/review-sentinel.service" \
  "$HOME/.config/systemd/user/review-sentinel.service"
systemctl --user daemon-reload >/dev/null 2>&1 || true
if PYTHONPATH="$HOME/.local/lib/review-sentinel" \
  "$python_bin" -m review_sentinel.cli \
  --env-file "$HOME/.config/review-sentinel/review-sentinel.env" doctor; then
  printf '%s\n' 'review-sentinel doctor: ready'
else
  printf '%s\n' 'review-sentinel installed but inactive: configure the GitHub App credentials and allowlist first'
fi
printf '%s\n' 'service is intentionally not enabled or started by the installer'
