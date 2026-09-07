#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "$script_dir/.." && pwd)

# shellcheck source=../config/build.env
source "$project_dir/config/build.env"

: "${FIRMWARE_VARIANT:?FIRMWARE_VARIANT is required}"
: "${OVERLAY_DIR:=/workspace/overlay}"
: "${OUTPUT_DIR:=/workspace/out}"

case "$FIRMWARE_VARIANT" in
	home-bypass | office-gateway) ;;
	*)
		echo "unsupported firmware variant: $FIRMWARE_VARIANT" >&2
		exit 2
		;;
esac

[[ -d "$OVERLAY_DIR" ]]
[[ -f "$OVERLAY_DIR/etc/firmware_variant.txt" ]]
mkdir -p "$OUTPUT_DIR"

cd /home/build/immortalwrt

rm -rf packages
mkdir -p packages /tmp/nikki-feed

curl --fail --location --retry 3 --retry-delay 2 \
	--output "/tmp/$NIKKI_ARCHIVE" "$NIKKI_URL"
printf '%s  %s\n' "$NIKKI_SHA256" "/tmp/$NIKKI_ARCHIVE" |
	sha256sum --check -

tar -xzf "/tmp/$NIKKI_ARCHIVE" -C /tmp/nikki-feed
find /tmp/nikki-feed -maxdepth 1 -type f -name '*.apk' -exec cp -v {} packages/ \;

for expected in \
	'nikki-' \
	'luci-app-nikki-' \
	'luci-i18n-nikki-zh-cn-'
do
	compgen -G "packages/${expected}*.apk" >/dev/null || {
		echo "missing pinned Nikki package matching ${expected}*.apk" >&2
		exit 1
	}
done

cat >"$OUTPUT_DIR/build-parameters.txt" <<EOF
firmware_variant=$FIRMWARE_VARIANT
imagebuilder_image=$IMAGEBUILDER_IMAGE
immortalwrt_version=$IMMORTALWRT_VERSION
target=$TARGET
subtarget=$SUBTARGET
profile=$PROFILE
packages=$EXTRA_PACKAGES
files_overlay=$OVERLAY_DIR
rootfs_partsize_mib=$ROOTFS_PARTSIZE
image_type=squashfs-combined-efi.img.gz
upstream_sha=$UPSTREAM_SHA
nikki_version=$NIKKI_VERSION
nikki_archive=$NIKKI_ARCHIVE
nikki_sha256=$NIKKI_SHA256
EOF

make manifest \
	PROFILE="$PROFILE" \
	PACKAGES="$EXTRA_PACKAGES" |
	tee "$OUTPUT_DIR/full-manifest.txt"

make image \
	PROFILE="$PROFILE" \
	PACKAGES="$EXTRA_PACKAGES" \
	FILES="$OVERLAY_DIR" \
	ROOTFS_PARTSIZE="$ROOTFS_PARTSIZE"
