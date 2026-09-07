#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "$script_dir/.." && pwd)
repo_dir=$(cd -- "$project_dir/.." && pwd)

# shellcheck source=../config/build.env
source "$project_dir/config/build.env"

expected_packages='nikki luci-app-nikki luci-i18n-nikki-zh-cn luci-theme-argon luci-app-argon-config'
[[ "$EXTRA_PACKAGES" == "$expected_packages" ]]
[[ "$ROOTFS_PARTSIZE" == '8192' ]]
[[ "$PROFILE" == 'generic' ]]
[[ "$IMMORTALWRT_VERSION" == '25.12.1' ]]
[[ "$ZASHBOARD_URL" == 'https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip' ]]
[[ "$NIKKI_API_LISTEN" == '[::]:9090' ]]
[[ "$NIKKI_API_SECRET" == 'abc123' ]]

bash -n "$project_dir"/scripts/*.sh "$project_dir"/tests/*.sh "$project_dir"/tests/mock-bin/uci
sh -n "$project_dir/files/etc/uci-defaults/99zz-dual-firmware"

if command -v shellcheck >/dev/null 2>&1; then
	shellcheck \
		"$project_dir"/scripts/*.sh \
		"$project_dir"/tests/*.sh \
		"$project_dir"/tests/mock-bin/uci \
		"$project_dir/files/etc/uci-defaults/99zz-dual-firmware"
fi

if grep -Eq 'nikki\.mixin\.tun_|uci[[:space:]]+(set|add_list|delete)[[:space:]].*tun_' \
	"$project_dir/files/etc/uci-defaults/99zz-dual-firmware"
then
	echo "custom firstboot script modifies a TUN field" >&2
	exit 1
fi

if grep -Eiq '(chpasswd|passwd[[:space:]]+root|root:[^:]+:)' \
	"$project_dir/files/etc/uci-defaults/99zz-dual-firmware"
then
	echo "root credential customization detected" >&2
	exit 1
fi

if find "$project_dir/files" -type f \( -name '*.yaml' -o -name '*.yml' \) |
	grep -q .
then
	echo "YAML file found in firmware overlay" >&2
	exit 1
fi

workflow="$repo_dir/.github/workflows/build-x86-64-dual-firmware.yml"
[[ -f "$workflow" ]]
grep -Fq "ROOTFS_PARTSIZE: '8192'" "$workflow"
grep -Fq 'permissions:' "$workflow"

"$project_dir/tests/run-firstboot-tests.sh"
echo "static_validation=passed"
