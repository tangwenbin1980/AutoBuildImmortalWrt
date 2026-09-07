#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 4 ]]; then
	echo "usage: $0 <variant> <image.gz> <forbidden-packages> <report-dir>" >&2
	exit 2
fi

variant=$1
image=$2
forbidden_file=$3
report_dir=$4

case "$variant" in
	home-bypass | office-gateway) ;;
	*)
		echo "unsupported firmware variant: $variant" >&2
		exit 2
		;;
esac

mkdir -p "$report_dir"
work_dir=$(mktemp -d)
raw_image="$work_dir/firmware.img"
mount_dir="$work_dir/rootfs"
loop_device=''
mounted=0

cleanup() {
	set +e
	if [[ $mounted -eq 1 ]]; then
		sudo umount "$mount_dir"
	fi
	if [[ -n "$loop_device" ]]; then
		sudo losetup -d "$loop_device"
	fi
	rm -rf "$work_dir"
}
trap cleanup EXIT

gzip -dc "$image" |
	dd of="$raw_image" bs=4M conv=sparse status=none

loop_device=$(sudo losetup --find --show --partscan "$raw_image")
sudo udevadm settle

lsblk -lnpo NAME,TYPE,FSTYPE,PARTLABEL,SIZE "$loop_device" |
	tee "$report_dir/partition-layout.txt"

lsblk -lnpo FSTYPE "$loop_device" | grep -Eiq '^(vfat|fat|fat16|fat32)$' || {
	echo "EFI/FAT boot partition not found" >&2
	exit 1
}

root_partition=$(lsblk -lnpo NAME,FSTYPE "$loop_device" |
	awk '$2 == "squashfs" { print $1; exit }')
[[ -n "$root_partition" ]] || {
	echo "squashfs root partition not found" >&2
	exit 1
}

rootfs_bytes=$(sudo blockdev --getsize64 "$root_partition")
minimum_bytes=$((8192 * 1024 * 1024))
if ((rootfs_bytes < minimum_bytes)); then
	echo "root partition is smaller than 8192 MiB: $rootfs_bytes" >&2
	exit 1
fi

mkdir -p "$mount_dir"
sudo mount -o ro "$root_partition" "$mount_dir"
mounted=1

grep -Fxq "firmware_variant=$variant" "$mount_dir/etc/firmware_variant.txt"

root_password=$(
	awk -F: '$1 == "root" { print $2; exit }' "$mount_dir/etc/shadow"
)
[[ -z "$root_password" ]] || {
	echo "root password field is not empty" >&2
	exit 1
}

[[ -f "$mount_dir/lib/apk/db/installed" ]]
awk -F: '$1 == "P" { print $2 }' "$mount_dir/lib/apk/db/installed" |
	sort -u >"$report_dir/installed-packages.txt"

required=(
	nikki
	luci-app-nikki
	luci-i18n-nikki-zh-cn
	luci-theme-argon
	luci-app-argon-config
)
for package in "${required[@]}"; do
	grep -Fxq "$package" "$report_dir/installed-packages.txt" || {
		echo "required package missing from final image: $package" >&2
		exit 1
	}
done

while IFS= read -r package; do
	[[ -n "$package" ]] || continue
	if grep -Fxq "$package" "$report_dir/installed-packages.txt"; then
		echo "forbidden package found in final image: $package" >&2
		exit 1
	fi
done <"$forbidden_file"

if [[ -d "$mount_dir/etc/nikki/run/ui" ]] &&
	find "$mount_dir/etc/nikki/run/ui" -mindepth 1 -print -quit | grep -q .
then
	echo "offline Nikki dashboard content is present" >&2
	exit 1
fi

firstboot="$mount_dir/etc/uci-defaults/99zz-dual-firmware"
[[ -x "$firstboot" ]]
grep -Fq 'nikki.mixin.api_listen=[::]:9090' "$firstboot"
grep -Fq 'nikki.mixin.api_secret=abc123' "$firstboot"
grep -Fq 'https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip' "$firstboot"
if grep -Eq 'nikki\.mixin\.tun_|uci[[:space:]]+(set|add_list|delete)[[:space:]].*tun_' "$firstboot"; then
	echo "custom firstboot script modifies a TUN field" >&2
	exit 1
fi

cat >"$report_dir/image-inspection.txt" <<EOF
variant=$variant
combined_efi=passed
squashfs_root=passed
rootfs_partition_bytes=$rootfs_bytes
root_password_empty=passed
required_packages=passed
forbidden_packages=passed
offline_dashboard_absent=passed
controller_whitelist=passed
tun_customization_absent=passed
EOF

cat "$report_dir/image-inspection.txt"
