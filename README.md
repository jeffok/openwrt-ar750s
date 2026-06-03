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
| 代理核心 | mihomo + luci-app-mihomo |
| Web 界面 | LuCI（中文）+ ttyd 终端 |
| DNS | dnsmasq-full（支持 nftset/DHCP） |
| WiFi 认证 | wpad-openssl（支持 WPA3） |
| 透明代理 | kmod-nft-tproxy + kmod-tcp-bbr |
| USB LTE | 华为 E372（NCM 模式）+ usb-modeswitch |
| SD 卡扩展 | kmod-fs-ext4 + e2fsprogs + fdisk（extroot） |
| 基础工具 | curl、wget-ssl、tcpdump、ip-full、htop |
| 网络诊断 | mtr、ping、netstat（net-tools）、bind-dig、bind-nslookup、iperf3、ethtool、netcat |

## 默认配置

- 管理地址：`http://192.168.1.1`
- 初始密码：**`password`**（首次登录后建议修改）

## 获取固件

push 修改 `.config` 后 GitHub Actions 自动构建，完成后在 Actions 页面 **Artifacts** 中下载（保留 90 天）。

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

## 内核补丁说明

本固件在 Lean LEDE 源码基础上增加了以下关键修复：

**以太网驱动修复（kernel 6.6）**

kernel 6.6 中，`ag71xx_legacy` 以太网驱动与 `syscon` 框架存在 reset control 冲突（`-EBUSY`），导致 MDIO probe 失败、有线网口全部消失。修复方式：在编译时向 `ath79.dtsi` 注入 `syscon-no-reset` 属性，绕过冲突（对应 LEDE 补丁 `820-mfd-syscon-support-skip-reset-control-for-syscon-devices`）。

## 常用诊断命令

```bash
# 连通性测试
ping 8.8.8.8

# 路径追踪（显示每跳延迟和丢包，实时刷新）
mtr 8.8.8.8

# 查看当前连接和端口占用
netstat -tulnp          # 监听端口
netstat -an             # 所有连接

# DNS 查询
dig google.com @8.8.8.8
nslookup google.com

# 带宽测试（需两端都有 iperf3）
iperf3 -s               # 路由器作服务端
iperf3 -c 192.168.1.1   # 客户端连路由器测速

# 以太网链路状态（速率、双工、驱动）
ethtool eth0

# 端口连通性测试
nc -zv 8.8.8.8 53
```

## 致谢

- [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) — 源码
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) — workflow 参考
- [morytyann/OpenWrt-mihomo](https://github.com/morytyann/OpenWrt-mihomo) — mihomo feed
