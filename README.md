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
| 内核 | Linux 6.6（含以太网驱动补丁） |
| 源码 | coolsnowwolf/lede master |

## 内置功能

| 分类 | 包 |
|------|----|
| 代理核心 | Nikki + mihomo-meta（Clash 订阅、Mihomo 智能 DNS） |
| Web 界面 | LuCI（中文）+ ttyd 终端 |
| DNS | Mihomo 分流 DNS + dnsmasq-full（DHCP/nftset） |
| WiFi 认证 | wpad-openssl（支持 WPA3） |
| 透明代理 | kmod-nft-tproxy + kmod-tcp-bbr |
| USB LTE | 华为 E372（NCM 模式）+ usb-modeswitch |
| SD 卡 | kmod-phy-ath79-usb + USB 存储 + ext4/vfat（内置 USB 读卡器） |
| 基础工具 | curl、wget-ssl、tcpdump、ip-full、htop |
| 网络诊断 | mtr、netstat（net-tools）；dig/iperf3 等可按需 opkg 安装 |

## 默认配置

- 管理地址：`http://192.168.1.1`
- 初始密码：**`password`**（首次登录后建议修改）

## 获取固件

push 修改 `.config` 后 GitHub Actions 自动构建，完成后在 Actions 页面 **Artifacts** 中下载（保留 90 天）。

## 刷机方法（GL-AR750S NOR+NAND 必看）

本机型为 **NOR 内核 + NAND 根文件系统**。`squashfs-sysupgrade.bin` 是 **tar 包**，只能由系统里的 `sysupgrade` 解包写入，**不能**在 U-Boot 里当普通 bin 直刷（会写坏 Flash，重启后一直停在 initramfs）。

### 标准两步刷机（推荐）

**第一步：U-Boot 只刷 initramfs（进临时系统）**

1. 网线连接 LAN 口，电脑设 `192.168.1.2`
2. 断电，按住 **Reset** 上电，LED 快闪后松手
3. 浏览器打开 `http://192.168.1.1`，上传 **`*-initramfs-kernel.bin`**
4. 启动后用 `http://192.168.1.1` 登录，密码 **`password`**

**第二步：在 initramfs 里 sysupgrade 永久固件**

```bash
wifi down
rm -f /tmp/sysupgrade.bin

# Mac 固件目录开 HTTP（把 IP 换成你电脑的）
# python3 -m http.server 8080

# 路由器拉取（示例 IP 192.168.1.100）
wget -O /tmp/sysupgrade.bin http://192.168.1.100:8080/openwrt-ath79-nand-glinet_gl-ar750s-nor-nand-squashfs-sysupgrade.bin
ls -lh /tmp/sysupgrade.bin    # 须约 14MB

# 先测试镜像是否匹配本机
sysupgrade -T /tmp/sysupgrade.bin

# 正式刷入（会重启）
sysupgrade -n /tmp/sysupgrade.bin
```

刷机成功后 **不应再出现** LuCI 黄条「initramfs 恢复模式」。若仍有，说明镜像过旧或 `sysupgrade` 未成功，需用**含 metadata 修复**的新固件重刷。

### 已在永久系统内升级

```bash
sysupgrade -n /tmp/openwrt-ath79-nand-glinet_gl-ar750s-nor-nand-squashfs-sysupgrade.bin
```

## 固件文件说明

| 文件 | 用途 |
|------|------|
| `*-initramfs-kernel.bin` | **U-Boot 第一步**：临时启动，用于执行 sysupgrade |
| `*-squashfs-sysupgrade.bin` | **第二步 sysupgrade**：写入 NOR 内核 + NAND 系统，勿在 U-Boot 直刷 |

## 内核补丁说明

本固件在 Lean LEDE 源码基础上增加了以下关键修复：

**以太网驱动修复（kernel 6.6）**

kernel 6.6 中，`ag71xx_legacy` 与 `syscon` 争用 reset → MDIO `-EBUSY` → 无有线。编译时向 `ath79.dtsi` 注入 `syscon-no-reset`（LEDE 补丁 820）。

**sysupgrade 元数据修复（nor-nand）**

LEDE 上游 `nand.mk` 中 nor-nand 镜像的 `SUPPORTED_DEVICES` 漏写 `glinet,gl-ar750s-nor-nand`，会导致 `sysupgrade` 校验失败、刷完仍停在 initramfs。构建时已自动补丁并 CI 校验 metadata。

## 代理（Nikki）使用说明

1. LuCI → **服务 → Nikki**，启用插件并填入 Clash 订阅 URL（或上传 YAML 配置）。
2. 订阅内若含 `type: wireguard` 节点，由 Mihomo 核心直接支持；纯 `.conf` 格式 WG 订阅需自行转换或另配 `wireguard`。
3. 在 Nikki 中开启 **DNS 劫持** 与 **局域网/本机代理**；LuCI **网络 → DHCP/DNS** 中关闭「DNS 重定向」，避免与 Mihomo DNS 冲突。
4. 固件已禁用 KMS（`vlmcsd`）；系统自带 `firewall4` 保留（NAT 必需），无需额外安装 OpenClash。

## SD 卡（microSD）说明

AR750S 卡槽为 **内置 USB 读卡器**（非 `mmcblk`），设备名为 `/dev/sda`。固件已包含 `kmod-phy-ath79-usb`（USB PHY，缺此模块则整机 USB 不工作）。

刷机后验证：

```bash
lsusb                          # 应看到 05e3:0723 等 USB 设备
block info                     # 应有 /dev/sda1
lsmod | grep phy-ar7200        # PHY 模块应已加载
```

若卡为 FAT32，已含 `kmod-fs-vfat`；ext4 卡用 `mkfs.ext4 /dev/sda1` 后于 **挂载点** 或 extroot 配置挂载。

**若 `lsusb` 报 `libusb: -99` 且无 `/dev/sda`**：说明固件未编入 `kmod-phy-ath79-usb`（USB PHY 未加载）。请使用**含 workflow 校验修复**之后的新固件重刷，不要继续用漏包的旧镜像。

## 常用诊断命令

```bash
# 连通性测试
ping 8.8.8.8

# 路径追踪（显示每跳延迟和丢包，实时刷新）
mtr 8.8.8.8

# 查看当前连接和端口占用
netstat -tulnp          # 监听端口
netstat -an             # 所有连接

# DNS 查询（未预装 dig 时可用 nslookup，或 opkg install bind-dig）
nslookup google.com
```

## 致谢

- [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) — 源码
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) — workflow 参考
- [morytyann/OpenWrt-mihomo](https://github.com/morytyann/OpenWrt-mihomo) — Nikki / mihomo-meta feed
- [nikkinikki-org/OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki) — Nikki 文档与 Wiki
