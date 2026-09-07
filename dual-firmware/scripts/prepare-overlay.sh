#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 2 ]]; then
	echo "usage: $0 <home-bypass|office-gateway> <overlay-dir>" >&2
	exit 2
fi

variant=$1
overlay_dir=$2
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "$script_dir/.." && pwd)
repo_dir=$(cd -- "$project_dir/.." && pwd)
workspace_dir=${GITHUB_WORKSPACE:-$repo_dir}

# shellcheck source=../config/build.env
source "$project_dir/config/build.env"

case "$variant" in
	home-bypass)
		management_address='10.0.0.2'
		;;
	office-gateway)
		management_address='192.168.10.1'
		;;
	*)
		echo "unsupported firmware variant: $variant" >&2
		exit 2
		;;
esac

overlay_parent=$(cd -- "$(dirname -- "$overlay_dir")" && pwd)
overlay_abs="$overlay_parent/$(basename -- "$overlay_dir")"
case "$overlay_abs" in
	"$project_dir"/* | "$workspace_dir"/*) ;;
	*)
		echo "refusing to prepare overlay outside the project/workspace: $overlay_abs" >&2
		exit 1
		;;
esac

rm -rf -- "$overlay_abs"
mkdir -p -- "$overlay_abs"
cp -a -- "$project_dir/files/." "$overlay_abs/"
chmod 0755 "$overlay_abs/etc/uci-defaults/99zz-dual-firmware"

mkdir -p "$overlay_abs/etc"
cat >"$overlay_abs/etc/firmware_variant.txt" <<EOF
firmware_variant=$variant
management_address=$management_address
immortalwrt_version=$IMMORTALWRT_VERSION
target=$TARGET
subtarget=$SUBTARGET
profile=$PROFILE
rootfs_partsize_mib=$ROOTFS_PARTSIZE
upstream_sha=$UPSTREAM_SHA
workflow_sha=${GITHUB_SHA:-local}
EOF

while IFS= read -r -d '' file; do
	sed -i 's/\r$//' "$file"
done < <(find "$overlay_abs" -type f -print0)

printf 'overlay=%s\nvariant=%s\nmanagement_address=%s\n' \
	"$overlay_abs" "$variant" "$management_address"
