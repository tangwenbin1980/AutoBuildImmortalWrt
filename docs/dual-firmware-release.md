# 双固件构建与发布基线

## 固定基线

| 项目 | 值 |
| --- | --- |
| 唯一上游 | `wukongdaily/ImmortalWrt-ImageBuilder` |
| 上游 SHA | `2fad7e1571f35c39831d761a7359480c7e3815e7` |
| ImmortalWrt | `25.12.1` |
| ImageBuilder | `immortalwrt/imagebuilder:x86-64-openwrt-25.12.1` |
| Target | `x86/64` |
| Profile | `generic` |
| ROOTFS_PARTSIZE | `8192` MiB |
| Nikki | `v1.26.0` |

## 交付文件

- `immortalwrt-25.12.1-x86-64-home-bypass-8g-nikki-squashfs-combined-efi.img.gz`
- `immortalwrt-25.12.1-x86-64-office-gateway-8g-nikki-squashfs-combined-efi.img.gz`

每个镜像配有独立 SHA256、完整安装包 manifest、构建参数和最终镜像检查报告。

## 发布原则

只有两个矩阵构建、最终镜像解包检查和 QEMU/UEFI 启动测试全部成功，Release job 才获得 `contents: write` 权限并发布。独立 rootfs、ext4、ISO 和其他 ImageBuilder 中间产物不会进入交付资产。
