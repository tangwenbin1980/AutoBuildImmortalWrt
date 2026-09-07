#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 3 ]]; then
	echo "usage: $0 <variant> <bin-dir> <output-dir>" >&2
	exit 2
fi

variant=$1
bin_dir=$2
output_dir=$3

case "$variant" in
	home-bypass)
		filename='immortalwrt-25.12.1-x86-64-home-bypass-8g-nikki-squashfs-combined-efi.img.gz'
		;;
	office-gateway)
		filename='immortalwrt-25.12.1-x86-64-office-gateway-8g-nikki-squashfs-combined-efi.img.gz'
		;;
	*)
		echo "unsupported firmware variant: $variant" >&2
		exit 2
		;;
esac

mapfile -d '' images < <(
	find "$bin_dir/targets/x86/64" -maxdepth 1 -type f \
		-name '*squashfs-combined-efi.img.gz' -print0
)

if [[ ${#images[@]} -ne 1 ]]; then
	printf 'expected exactly one combined EFI image, found %d\n' "${#images[@]}" >&2
	exit 1
fi

mkdir -p "$output_dir/release"
cp -- "${images[0]}" "$output_dir/release/$filename"

if find "$output_dir/release" -maxdepth 1 -type f \
	\( -name '*rootfs.img.gz' -o -name '*ext4*.img.gz' -o -name '*.iso' \) |
	grep -q .
then
	echo "non-deliverable image found in release staging" >&2
	exit 1
fi

(
	cd "$output_dir/release"
	sha256sum "$filename" >"$filename.sha256"
	sha256sum --check "$filename.sha256"
)

bytes=$(stat -c '%s' "$output_dir/release/$filename")
sha256=$(sha256sum "$output_dir/release/$filename" | awk '{print $1}')
printf 'artifact=%s\nbytes=%s\nsha256=%s\n' \
	"$filename" "$bytes" "$sha256" |
	tee "$output_dir/artifact-metadata.txt"
