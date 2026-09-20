#!/bin/sh
# 对一棵远端目录树逐文件算 sha256,输出 "hash  相对路径"。
# 用于替代 AI-Ops 41 runbook 里手工的"逐文件 sha256 对比"必做步骤。
# 用法: hash-tree.sh TARGET BASE_DIR
set -eu
target=$1
base=${2:-.}
"$(CDPATH= cd -- "$(dirname "$0")" && pwd)/bin/dev-host" exec "$target" --allow-service-exec -- \
  "cd $(printf "'%s'" "$base") && find . -type f -exec sha256sum {} + | sort -k2"
