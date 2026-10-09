#!/usr/bin/env bash
# check_commit_msg.sh 的自测：CI 里先跑它，避免闸门本身悄悄失效。
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook="$root/tool/check_commit_msg.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

expect_ok() {
  local name="$1"
  local file="$tmp/ok-$pass.txt"
  printf '%s\n' "$name" > "$file"
  if bash "$hook" "$file" >/dev/null 2>&1; then
    pass=$((pass + 1))
  else
    echo "预期通过但失败了：$name" >&2
    fail=$((fail + 1))
  fi
}

expect_rejected() {
  local name="$1"
  local file="$tmp/bad-$fail.txt"
  printf '%s' "$name" > "$file"
  if bash "$hook" "$file" >/dev/null 2>&1; then
    echo "预期被拒但通过了：$name" >&2
    fail=$((fail + 1))
  else
    pass=$((pass + 1))
  fi
}

expect_ok 'feat(session): 增加频道切换命令'
expect_ok 'fix(policy): reject look-alike domains'
expect_ok 'docs: 记录合规策略的决策'
expect_ok 'refactor(core,ffi)!: 收紧 FFI 边界'
expect_ok 'Merge branch main'
expect_ok 'Revert "feat: 试一个新东西"'

expect_rejected '增加频道切换命令'
expect_rejected 'feat(session) 增加频道切换命令'
expect_rejected 'feat(session): Reject look-alike domains'
expect_rejected 'feat(session): 加个尾巴。'
expect_rejected "$(printf 'feat(session): %s' "$(head -c 120 < /dev/zero | tr '\0' 'a')")"
expect_rejected "$(printf 'feat(session): 收紧边界\n\nCo-authored-by: Claude <noreply@anthropic.com>\n')"

if [[ "$fail" -ne 0 ]]; then
  echo "提交信息闸门自测失败：$fail 个用例" >&2
  exit 1
fi

echo "提交信息闸门自测通过：$pass 个用例"