#!/usr/bin/env bash
# 校验提交信息是否符合 Conventional Commits 与本仓库的约定。
#
# 用法：
#   check_commit_msg.sh <message-file>          # commit-msg 钩子 / 单条
#   check_commit_msg.sh <base-rev> <head-rev>   # CI：检查区间内每条提交
set -euo pipefail

types='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'
agents='anthropic|claude|codex|copilot|cursor|devin|gemini|openai|\[bot\]'

validate() {
  local message_file="$1"
  local cleaned subject description first_word

  cleaned="$(grep -v '^#' "$message_file" | sed '/[^[:space:]]/,$!d' || true)"
  subject="$(head -n 1 <<<"$cleaned")"

  if [[ -z "$subject" ]]; then
    echo '提交信息为空。' >&2
    return 1
  fi

  # Merge/Revert/fixup! 不参与格式校验。
  if [[ "$subject" =~ ^(Merge|Revert)[[:space:]] || "$subject" =~ ^(fixup|squash)! ]]; then
    return 0
  fi

  if [[ ! "$subject" =~ ^($types)(\([a-z0-9,./_-]+\))?!?:[[:space:]].+ ]]; then
    cat >&2 <<EOF
提交标题不符合 Conventional Commits：

  $subject

期望：<type>[(scope)][!]: <description>
可用类型：${types//|/, }
示例：
  feat(session): 增加频道切换命令
  fix(policy): 拒绝带点前缀的短昵称
EOF
    return 1
  fi

  if [[ ${#subject} -gt 100 ]]; then
    echo "提交标题 ${#subject} 个字符，请控制在 100 以内。" >&2
    return 1
  fi

  description="${subject#*: }"
  first_word="${description%% *}"
  first_word="${first_word%%[^[:alnum:]]*}"

  if [[ "$first_word" =~ ^[A-Z][a-z]+$ ]]; then
    echo "描述请用小写开头：$description" >&2
    echo '标识符与缩写保留自身大小写，例如 AppBar、DNS。' >&2
    return 1
  fi

  if [[ "$description" =~ (\.[[:space:]]*|。)$ ]]; then
    echo "描述结尾不要加句号：$description" >&2
    return 1
  fi

  if grep -qiE "^Co-authored-by:.*($agents)" <<<"$(tail -n +2 <<<"$cleaned")"; then
    cat >&2 <<'EOF'
不要在 Co-authored-by 里署名编码代理。

历史记录的是谁对改动负责，而不是哪个工具敲的字。人类共同作者仍然可以写。
EOF
    return 1
  fi

  return 0
}

if [[ $# -eq 1 ]]; then
  validate "$1"
  exit $?
fi

if [[ $# -eq 2 ]]; then
  base="$1"
  head="$2"
  status=0
  tmp="$(mktemp)"
  while IFS= read -r sha; do
    git log -1 --format=%B "$sha" > "$tmp"
    if ! validate "$tmp"; then
      echo "（提交 $sha）" >&2
      status=1
    fi
  done < <(git rev-list "$base..$head")
  rm -f "$tmp"
  exit "$status"
fi

echo "用法：check_commit_msg.sh <message-file> | <base-rev> <head-rev>" >&2
exit 2