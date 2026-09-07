#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
project_dir=$(cd -- "$script_dir/.." && pwd)
firstboot="$project_dir/files/etc/uci-defaults/99zz-dual-firmware"
mock_bin="$project_dir/tests/mock-bin"

assert_value() {
	local state=$1
	local key=$2
	local expected=$3
	local actual
	actual=$(awk -F= -v key="$key" '$1 == key { value=$0; sub(/^[^=]*=/, "", value); print value; exit }' "$state")
	[[ "$actual" == "$expected" ]] || {
		echo "assertion failed: $key expected=$expected actual=$actual" >&2
		exit 1
	}
}

assert_missing() {
	local state=$1
	local key=$2
	if awk -F= -v key="$key" '$1 == key { found=1 } END { exit !found }' "$state"; then
		echo "assertion failed: expected missing key $key" >&2
		exit 1
	fi
}

seed_state() {
	local state=$1
	cat >"$state" <<'EOF'
network.br_lan=device
network.br_lan.name=br-lan
network.br_lan.type=bridge
network.br_lan.ports=old0
network.lan=interface
network.lan.device=br-lan
network.lan.proto=static
network.lan.ipaddr=192.168.1.1
network.wan=interface
network.wan.device=eth9
network.wan.proto=dhcp
network.wan6=interface
network.wan6.device=eth9
network.wan6.proto=dhcpv6
dhcp.lan=dhcp
dhcp.lan.ignore=0
firewall.wan=zone
firewall.wan.name=wan
firewall.wan.masq=1
firewall.default_forwarding=forwarding
firewall.default_forwarding.src=lan
firewall.default_forwarding.dest=wan
firewall.keep_redirect=redirect
firewall.keep_redirect.src=wan
nikki.mixin=mixin
nikki.mixin.api_listen=[::]:9091
nikki.mixin.api_secret=random
nikki.mixin.ui_url=https://example.invalid/ui.zip
nikki.mixin.tun_enabled=1
nikki.mixin.tun_device=nikki
nikki.mixin.tun_stack=mixed
nikki.mixin.tun_mtu=9000
nikki.mixin.tun_dns_hijack=0
EOF
}

create_interface() {
	local sysfs=$1
	local name=$2
	mkdir -p "$sysfs/$name/device"
}

run_variant() {
	local variant=$1
	shift
	local temp
	temp=$(mktemp -d)
	local state="$temp/uci-state"
	local sysfs="$temp/sys/class/net"
	local variant_file="$temp/firmware_variant.txt"
	local log_file="$temp/firstboot.log"

	mkdir -p "$sysfs"
	seed_state "$state"
	printf 'firmware_variant=%s\n' "$variant" >"$variant_file"
	for interface in "$@"; do
		create_interface "$sysfs" "$interface"
	done
	mkdir -p "$sysfs/lo"

	local tun_before
	tun_before=$(grep '^nikki\.mixin\.tun_' "$state" | sort)

	PATH="$mock_bin:$PATH" \
	MOCK_UCI_STATE="$state" \
	SYS_CLASS_NET="$sysfs" \
	FIRMWARE_VARIANT_FILE="$variant_file" \
	DUAL_FIRMWARE_LOGFILE="$log_file" \
		sh "$firstboot"

	local first_hash
	first_hash=$(sha256sum "$state" | awk '{print $1}')

	PATH="$mock_bin:$PATH" \
	MOCK_UCI_STATE="$state" \
	SYS_CLASS_NET="$sysfs" \
	FIRMWARE_VARIANT_FILE="$variant_file" \
	DUAL_FIRMWARE_LOGFILE="$log_file" \
		sh "$firstboot"

	local second_hash
	second_hash=$(sha256sum "$state" | awk '{print $1}')
	[[ "$first_hash" == "$second_hash" ]] || {
		echo "$variant is not idempotent" >&2
		exit 1
	}

	local tun_after
	tun_after=$(grep '^nikki\.mixin\.tun_' "$state" | sort)
	[[ "$tun_before" == "$tun_after" ]] || {
		echo "$variant modified TUN fields" >&2
		exit 1
	}

	assert_value "$state" 'nikki.mixin.api_listen' '[::]:9090'
	assert_value "$state" 'nikki.mixin.api_secret' 'abc123'
	assert_value "$state" 'nikki.mixin.ui_url' 'https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip'

	case "$variant" in
		home-bypass)
			assert_value "$state" 'network.lan.ipaddr' '10.0.0.2'
			assert_value "$state" 'network.lan.gateway' '10.0.0.1'
			assert_value "$state" 'dhcp.lan.ignore' '1'
			assert_value "$state" 'network.wan.auto' '0'
			assert_value "$state" 'network.wan.disabled' '1'
			assert_missing "$state" 'network.wan.device'
			assert_value "$state" 'network.wan6.auto' '0'
			assert_value "$state" 'network.wan6.disabled' '1'
			assert_missing "$state" 'network.wan6.device'
			assert_missing "$state" 'firewall.default_forwarding'
			;;
		office-gateway)
			assert_value "$state" 'network.lan.ipaddr' '192.168.10.1'
			assert_value "$state" 'network.wan.device' 'eth0'
			assert_value "$state" 'network.wan.proto' 'dhcp'
			assert_value "$state" 'dhcp.lan.start' '100'
			assert_value "$state" 'dhcp.lan.limit' '150'
			assert_value "$state" 'dhcp.lan.leasetime' '12h'
			assert_value "$state" 'firewall.wan.masq' '1'
			assert_value "$state" 'firewall.dual_lan_wan.src' 'lan'
			assert_value "$state" 'firewall.dual_lan_wan.dest' 'wan'
			;;
	esac

	assert_value "$state" 'firewall.keep_redirect.src' 'wan'
	rm -rf "$temp"
}

run_variant home-bypass eth0 eth1 eth2
run_variant office-gateway eth0 eth1 eth2

failure_temp=$(mktemp -d)
seed_state "$failure_temp/uci-state"
mkdir -p "$failure_temp/sys/class/net/eth0/device"
printf 'firmware_variant=office-gateway\n' >"$failure_temp/variant"
if PATH="$mock_bin:$PATH" \
	MOCK_UCI_STATE="$failure_temp/uci-state" \
	SYS_CLASS_NET="$failure_temp/sys/class/net" \
	FIRMWARE_VARIANT_FILE="$failure_temp/variant" \
	DUAL_FIRMWARE_LOGFILE="$failure_temp/log" \
		sh "$firstboot"
then
	echo "single-port office-gateway should fail" >&2
	exit 1
fi
rm -rf "$failure_temp"

echo "firstboot_tests=passed"
