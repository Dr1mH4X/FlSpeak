#!/usr/bin/env bash
# 把版本号写进 pubspec.yaml 与 workspace Cargo.toml。发版由 CI 用 tag 调用。
#
# 用法：set_version.sh <version> [build-number]
set -euo pipefail

version="${1:?用法: set_version.sh <version> [build-number]}"
build="${2:-1}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# BSD sed 与 GNU sed 都要能用，所以走 -i.bak 再删。
sed -i.bak -E "s/^version: .*/version: ${version}+${build}/" pubspec.yaml
sed -i.bak -E "s/^version = \"0\.0\.0\"/version = \"${version}\"/" Cargo.toml
rm -f pubspec.yaml.bak Cargo.toml.bak

echo "版本已写入：pubspec.yaml ${version}+${build}，Cargo.toml ${version}"