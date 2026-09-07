#!/usr/bin/env bash

set -Eeuo pipefail

if [[ $# -ne 3 ]]; then
	echo "usage: $0 <variant> <image.gz> <report-dir>" >&2
	exit 2
fi

variant=$1
image=$2
report_dir=$3

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
log_file="$report_dir/qemu-smoke.log"

cleanup() {
	rm -rf "$work_dir"
}
trap cleanup EXIT

gzip -dc "$image" |
	dd of="$raw_image" bs=4M conv=sparse status=none

ovmf_code=''
ovmf_vars=''
for directory in /usr/share/OVMF /usr/share/ovmf; do
	if [[ -f "$directory/OVMF_CODE_4M.fd" && -f "$directory/OVMF_VARS_4M.fd" ]]; then
		ovmf_code="$directory/OVMF_CODE_4M.fd"
		ovmf_vars="$directory/OVMF_VARS_4M.fd"
		break
	fi
	if [[ -f "$directory/OVMF_CODE.fd" && -f "$directory/OVMF_VARS.fd" ]]; then
		ovmf_code="$directory/OVMF_CODE.fd"
		ovmf_vars="$directory/OVMF_VARS.fd"
		break
	fi
done
[[ -n "$ovmf_code" && -n "$ovmf_vars" ]] || {
	echo "matching OVMF CODE/VARS firmware pair not found" >&2
	exit 1
}
ovmf_vars_copy="$work_dir/OVMF_VARS.fd"
cp "$ovmf_vars" "$ovmf_vars_copy"

if [[ "$variant" == 'home-bypass' ]]; then
	# shellcheck disable=SC2016
	guest_assertions='
test "$(uci -q get network.lan.ipaddr)" = "10.0.0.2"
test "$(uci -q get network.lan.gateway)" = "10.0.0.1"
test "$(uci -q get dhcp.lan.ignore)" = "1"
test "$(uci -q get network.wan.auto)" = "0"
test "$(uci -q get network.wan.disabled)" = "1"
test -z "$(uci -q get network.wan.device || true)"
test "$(uci -q get network.wan6.auto)" = "0"
test "$(uci -q get network.wan6.disabled)" = "1"
test -z "$(uci -q get network.wan6.device || true)"
'
else
	# shellcheck disable=SC2016
	guest_assertions='
test "$(uci -q get network.lan.ipaddr)" = "192.168.10.1"
test "$(uci -q get network.wan.device)" = "eth0"
test "$(uci -q get network.wan.proto)" = "dhcp"
test "$(uci -q get dhcp.lan.start)" = "100"
test "$(uci -q get dhcp.lan.limit)" = "150"
test "$(uci -q get dhcp.lan.leasetime)" = "12h"
test "$(uci -q get network.wan6.disabled)" = "1"
'
fi

export QEMU_VARIANT="$variant"
export QEMU_IMAGE="$raw_image"
export QEMU_OVMF_CODE="$ovmf_code"
export QEMU_OVMF_VARS="$ovmf_vars_copy"
export QEMU_LOG="$log_file"
export QEMU_GUEST_ASSERTIONS="$guest_assertions"

expect <<'EXPECT'
set timeout 300
log_file -noappend $env(QEMU_LOG)
spawn qemu-system-x86_64 \
	-machine accel=tcg \
	-m 512 \
	-nographic \
	-drive if=pflash,format=raw,readonly=on,file=$env(QEMU_OVMF_CODE) \
	-drive if=pflash,format=raw,file=$env(QEMU_OVMF_VARS) \
	-drive file=$env(QEMU_IMAGE),format=raw,if=virtio \
	-netdev user,id=net0 -device e1000,netdev=net0 \
	-netdev user,id=net1 -device e1000,netdev=net1 \
	-netdev user,id=net2 -device e1000,netdev=net2

expect {
	-re {Please press Enter to activate this console} {
		send "\r"
	}
	-re {root@.*:.*#} {}
	timeout {
		puts stderr "timed out waiting for the ImmortalWrt console"
		exit 1
	}
}

expect {
	-re {root@.*:.*#} {}
	timeout {
		puts stderr "timed out waiting for the root shell"
		exit 1
	}
}

send "set -eu\r"
send "grep -Fx 'firmware_variant=$env(QEMU_VARIANT)' /etc/firmware_variant.txt\r"
send "$env(QEMU_GUEST_ASSERTIONS)\r"
send "test \"\\$(uci -q get nikki.mixin.api_listen)\" = '[::]:9090'\r"
send "test \"\\$(uci -q get nikki.mixin.api_secret)\" = 'abc123'\r"
send "test \"\\$(uci -q get nikki.mixin.ui_url)\" = 'https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip'\r"
send "echo __DUAL_FIRMWARE_SMOKE_PASS__\r"

expect {
	"__DUAL_FIRMWARE_SMOKE_PASS__" {}
	timeout {
		puts stderr "guest assertions did not complete"
		exit 1
	}
}

send "poweroff\r"
expect eof
EXPECT

grep -Fq '__DUAL_FIRMWARE_SMOKE_PASS__' "$log_file"
if grep -Eiq 'kernel panic|not syncing|__DUAL_FIRMWARE_SMOKE_FAIL__' "$log_file"; then
	echo "QEMU boot log contains a fatal marker" >&2
	exit 1
fi

echo "qemu_smoke_test=passed" |
	tee "$report_dir/qemu-smoke-result.txt"
