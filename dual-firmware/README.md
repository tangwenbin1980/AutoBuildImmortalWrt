# ImmortalWrt 25.12.1 x86-64 双固件

本目录提供两个相互隔离的 ImageBuilder 变体：

- `home-bypass`：`10.0.0.2/24` 家庭旁路由。
- `office-gateway`：`192.168.10.1/24` 办公室二级网关。

共同固定项：

- ImageBuilder：`immortalwrt/imagebuilder:x86-64-openwrt-25.12.1`
- target/subtarget/profile：`x86/64/generic`
- `ROOTFS_PARTSIZE=8192`
- 只交付 `squashfs-combined-efi.img.gz`
- Nikki v1.26.0 的 x86_64 OpenWrt 25.12 发布包固定 SHA256
- 额外主动安装包只有 Nikki 三包和 Argon 两包
- Zashboard 只保留在线 URL，不内置面板
- root 初始密码不由本项目设置

首启脚本只设置网络角色和三个 Nikki 控制器字段，不修改任何 TUN 字段。办公室变体在检测不到 `eth0` 或没有第二个物理网口时返回失败，以便下次启动重试，而不是写入不可用拓扑。

运行离线验证：

```bash
dual-firmware/scripts/validate-static.sh
```

正式构建和 Release 由 `.github/workflows/build-x86-64-dual-firmware.yml` 手动触发。
