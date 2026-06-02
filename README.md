# GL-AR750S OpenWrt 定制固件

[![Build OpenWrt](https://github.com/jeffok/openwrt-ar750s/actions/workflows/build-openwrt.yml/badge.svg)](https://github.com/jeffok/openwrt-ar750s/actions/workflows/build-openwrt.yml)

基于 [Lean's LEDE](https://github.com/coolsnowwolf/lede) 为 **GL.iNet GL-AR750S-Ext** 编译的定制 OpenWrt 固件，通过 GitHub Actions 自动构建。

## 设备信息

| 项目 | 内容 |
|------|------|
| 设备 | GL.iNet GL-AR750S-Ext（Slate） |
| 架构 | ath79 / NAND |
| CPU | QCA9563 @ 775MHz |
| 内存 | 128MB RAM |
| 存储 | 16MB NOR + 128MB NAND |
| WiFi | 2.4GHz (ath9k) + 5GHz (ath10k) 双频 |
| 源码 | coolsnowwolf/lede master |

## 内置功能

| 分类 | 包 |
|------|----|
| 代理核心 | mihomo + luci-app-mihomo |
| Web 界面 | LuCI（中文）+ ttyd 终端 |
| DNS | dnsmasq-full（支持 nftset/DHCP） |
| WiFi 认证 | wpad-openssl（支持 WPA3） |
| 透明代理 | kmod-nft-tproxy + kmod-tcp-bbr |
| USB LTE | 华为 E372（NCM 模式）+ usb-modeswitch |
| SD 卡扩展 | kmod-fs-ext4 + e2fsprogs + fdisk（extroot） |
| 命令行工具 | curl、wget-ssl、tcpdump、ip-full、htop |

## 默认配置

- 管理地址：`http://192.168.1.1`
- 初始密码：无（首次登录后设置）

## 触发构建

以下情况会自动/手动触发 GitHub Actions 构建：

- 手动：Actions 页面点击 **Run workflow**
- 自动：push 修改 `.config` 文件时
- 自动：发布 Release 时

构建完成后在 Actions 页面 **Artifacts** 中下载固件（保留 90 天）。

## 刷机方法

### 从 U-Boot 救援模式全新刷入（推荐）

适用于：忘记密码、系统损坏、版本过旧无法 sysupgrade。

1. 电脑用网线连接路由器任意 **LAN 口**
2. 路由器断电，**按住 Reset 键**，插电，约 5 秒后 LED 快速闪烁时松手
3. 浏览器访问 `http://192.168.1.1`，出现 U-Boot Firmware Update 页面
4. 上传 `*-squashfs-sysupgrade.bin`，点击 **Update gl-inet firmware**
5. 等待 3~5 分钟，**不要断电**，LED 稳定后访问 `http://192.168.1.1`

### 从运行中的 OpenWrt 升级

```bash
# 上传固件到路由器
scp openwrt-ath79-nand-glinet_gl-ar750s-nor-nand-squashfs-sysupgrade.bin root@192.168.1.1:/tmp/

# SSH 进入后执行升级（-n 清空配置全新安装）
ssh root@192.168.1.1
sysupgrade -n /tmp/openwrt-ath79-nand-glinet_gl-ar750s-nor-nand-squashfs-sysupgrade.bin
```

## 固件文件说明

| 文件 | 用途 |
|------|------|
| `*-squashfs-sysupgrade.bin` | **主要刷机文件**，U-Boot 和 sysupgrade 均可使用 |
| `*-initramfs-kernel.bin` | 临时内核，仅在内存运行，用于救援调试 |

## 致谢

- [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) — 源码
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) — workflow 参考
- [morytyann/OpenWrt-mihomo](https://github.com/morytyann/OpenWrt-mihomo) — mihomo feed
