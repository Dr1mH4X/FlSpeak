#!/usr/bin/env bash
# 合规闸门：官方基础设施域名只允许出现在策略层（core/policy）。
#
# 文档、README 与策略 crate 自身可以讨论这些域名；其余任何源码、清单、CI 配置
# 只要出现官方域名就失败——避免有人绕过策略层直接连官方服务器。
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

source_file='core/policy/src/official_infra.rs'
if [[ ! -f "$source_file" ]]; then
  echo "缺少策略单一事实来源：$source_file" >&2
  exit 1
fi

patterns='teamspeak\.com|teamspeak-systems\.com|myteamspeak\.com'
status=0

while IFS= read -r file; do
  case "$file" in
    ./core/policy/*) continue ;;
    ./docs/* | ./.agents/* | ./README.md | ./LICENSE) continue ;;
    ./tool/audit_policy.sh) continue ;;
  esac
  if matches="$(grep -nEi "$patterns" "$file" || true)" && [[ -n "$matches" ]]; then
    printf '\n官方基础设施域名出现在 %s：\n%s\n' "$file" "$matches" >&2
    status=1
  fi
done < <(find . -type f \
  \( -name '*.rs' -o -name '*.dart' -o -name '*.yaml' -o -name '*.yml' \
  -o -name '*.toml' -o -name '*.json' -o -name '*.sh' -o -name '*.plist' \
  -o -name '*.xml' -o -name '*.gradle' -o -name '*.kts' \) \
  -not -path './target/*' -not -path './build/*' -not -path './dist/*' \
  -not -path './.dart_tool/*' -not -path './.git/*' -not -path './android/.gradle/*' \
  | sort)

if [[ "$status" -ne 0 ]]; then
  cat >&2 <<'EOF'

只允许 core/policy 声明官方域名与官方解析服务。
要放宽策略，请先写决策记录并修改那一处清单，不要在别处硬编码。
EOF
  exit 1
fi

echo '合规闸门通过：官方域名只出现在策略层。'