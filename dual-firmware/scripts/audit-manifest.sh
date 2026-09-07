#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
	echo "usage: $0 <manifest>" >&2
	exit 2
fi

manifest=$1
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "$script_dir/.." && pwd)
forbidden_file="$project_dir/config/forbidden-packages.txt"

[[ -s "$manifest" ]]

package_names=$(mktemp)
trap 'rm -f "$package_names"' EXIT

awk 'NF && $1 !~ /^WARNING:/ && $1 !~ /^Creating/ { print $1 }' "$manifest" |
	sed 's/[[:space:]]*$//' |
	sort -u >"$package_names"

required=(
	nikki
	luci-app-nikki
	luci-i18n-nikki-zh-cn
	luci-theme-argon
	luci-app-argon-config
)

for package in "${required[@]}"; do
	grep -Fxq "$package" "$package_names" || {
		echo "required package missing from manifest: $package" >&2
		exit 1
	}
done

while IFS= read -r package; do
	[[ -n "$package" ]] || continue
	if grep -Fxq "$package" "$package_names"; then
		echo "forbidden package present in manifest: $package" >&2
		exit 1
	fi
done <"$forbidden_file"

echo "manifest_policy=passed"
