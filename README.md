# GL-iNet GL-AR750S-Ext 路由器配置手册

> 基于 OpenWrt 23.05.5 官方固件，实现翻墙分流、SD卡扩展、智能DNS的完整配置方案。

---

## 设备信息

| 项目 | 内容 |
|------|------|
| 设备型号 | GL.iNet GL-AR750S-Ext（Slate） |
| CPU | Qualcomm Atheros QCA9563 MIPS 74Kc @ 775MHz（单核） |
| 内存 | 128MB RAM |
| 存储 | 16MB NOR + 128MB NAND |
| SD卡 | 14.5GB（extroot，挂载为 /overlay） |
| WiFi | 2.4GHz (QCA9560) + 5GHz (QCA9887) 双频 |
| 系统 | OpenWrt 23.05.5 r24106-10cc5fcd00 |
| 内核 | Linux 5.15.167 |

---

## 账号与访问信息

| 项目 | 内容 |
|------|------|
| 管理地址 | `http://192.168.254.254` |
| SSH | `ssh root@192.168.254.254` |
| 账号 | `root` |
| 密码 | `Wangke.0912` |
| WiFi SSID | `Jeff_ar750` |
| WiFi 密码 | `Wangke.0912` |
| WiFi 安全 | WPA2/WPA3 混合 |

---

## 网络拓扑

```
上游路由器/光猫（10.99.57.x）
      │ WAN（eth0.2，DHCP，当前 10.99.57.66，网关 10.99.57.253）
  AR750S（192.168.254.254/24）
      │ LAN（br-lan，192.168.254.100-249，DHCP）
  下游设备（手机/电脑）
      │
  WireGuard wg0 → 45.250.184.35:65029（全局翻墙出口）
```

---

## WiFi 配置

| 频段 | 频道 | 带宽 | SSID |
|------|------|------|------|
| 5GHz | 36（固定）| HT40 | Jeff_ar750 |
| 2.4GHz | 6（固定）| HT20 | Jeff_ar750 |

---

## SD 卡 extroot

| 分区 | 大小 | 格式 | 挂载点 |
|------|------|------|--------|
| /dev/sda1 | 14.8GB | ext4 | /overlay |

UUID: `106bc475-aa06-4f0a-962e-dde48c3188e4`

---

## 翻墙方案：WireGuard + nftset 分流 + SmartDNS 智能解析

### 架构

```
默认路由 → wg0（所有未命中的流量走 WG 翻墙）

直连分流（两套 nftset，prerouting 打 mark 0x1 → table 200 → eth0.2）：
  @cn_ip     国内 IP 段（~3700 CIDR，由 update-rules.sh 加载）
  @cn_domains 国内域名解析 IP（动态，由 SmartDNS 解析后实时回写）

精确直连路由（ip route，约 15 条）：
  WG endpoint（45.250.184.35）→ eth0.2 直连（隧道建立必须）
  国内 DNS（119.29.29.29 / 114.114.114.114 / 180.76.76.76）→ eth0.2 直连
  私有地址段（10.0.0.0/8、172.16.0.0/12、192.168.0.0/16）→ eth0.2 直连（内网可达）

WG 专用远端段（精确路由覆盖私有大段，确保走 wg0）：
  10.254.0.0/24  WG 隧道段
  10.100.50.0/24 远端内网 A
  192.168.88.0/23 远端内网 B

AllowedIPs 中不走 wg0 的段（显式覆盖回 eth0.2）：
  10.100.20.0/25 / 10.100.89.0/24

本机 LAN（192.168.254.0/24）→ br-lan（kernel 路由）
海外 DNS（8.8.8.8）→ 默认走 wg0

SmartDNS → DNS 防污染（监听 127.0.0.1:5335）
dnsmasq → 转发所有 DNS 到 SmartDNS（noresolv=1）
路由器自身 DNS → 127.0.0.1（peerdns=0，不被 WAN DHCP 覆盖）
```

**核心原则**：CN IP 段用 nftset 替代 ip route 批量写入，路由表保持 ~20 条精确路由，启动速度从 ~20s 降到 <1s，无 OOM 风险。

### 直连覆盖

| 机制 | 条数 | 说明 |
|------|------|------|
| nftset cn_ip | ~3700 CIDR | update-rules.sh 定期增量更新，永不 OOM |
| nftset cn_domains | 累积增长 | SmartDNS 解析国内域名后实时写入 |
| 精确 ip route | ~15 条 | WG endpoint、国内 DNS、私有段 |
| 合计覆盖率 | **95%+** | 两者互补 |

---

## WireGuard 配置

### 接口参数

| 参数 | 值 |
|------|-----|
| 接口名 | wg0 |
| 本机 IP | 10.254.0.30/30 |
| 本机公钥 | `Fgi9KeJT8oDrBebOhBtSGtC9pAfAljgbV7dop0YptAQ=` |
| 本机私钥 | `UJSUjN9fU4JV70VpfOwk2++kGvPv6YpBrmyGk4zv6Ww=` |
| MTU | 1420 |

### Peer（服务器端）

| 参数 | 值 |
|------|-----|
| 服务器 Endpoint | `45.250.184.35:65029` |
| 服务器公钥 | `IlKEqckX3dzBWbFYuvZdQfBgJ51mSTQQrj/tv0AGaxc=` |
| AllowedIPs | `0.0.0.0/0`（全部流量进隧道）|
| 远端内网 | `10.254.0.0/24, 10.100.50.0/24, 10.100.20.0/25, 10.100.89.0/24, 192.168.88.0/23` |
| Keepalive | 10 秒 |

### UCI 配置（恢复用）

```bash
uci set network.wg0=interface
uci set network.wg0.proto="wireguard"
uci set network.wg0.private_key="UJSUjN9fU4JV70VpfOwk2++kGvPv6YpBrmyGk4zv6Ww="
uci set network.wg0.addresses="10.254.0.30/30"
uci set network.wg0.mtu="1420"
uci set network.wg0.metric="0"

uci add network wireguard_wg0
uci set network.@wireguard_wg0[-1].public_key="IlKEqckX3dzBWbFYuvZdQfBgJ51mSTQQrj/tv0AGaxc="
uci set network.@wireguard_wg0[-1].endpoint_host="45.250.184.35"
uci set network.@wireguard_wg0[-1].endpoint_port="65029"
uci set network.@wireguard_wg0[-1].persistent_keepalive="10"
uci set network.@wireguard_wg0[-1].route_allowed_ips="0"
uci add_list network.@wireguard_wg0[-1].allowed_ips="0.0.0.0/0"
uci add_list network.@wireguard_wg0[-1].allowed_ips="10.254.0.0/24"
uci add_list network.@wireguard_wg0[-1].allowed_ips="10.100.50.0/24"
uci add_list network.@wireguard_wg0[-1].allowed_ips="10.100.20.0/25"
uci add_list network.@wireguard_wg0[-1].allowed_ips="10.100.89.0/24"
uci add_list network.@wireguard_wg0[-1].allowed_ips="192.168.88.0/23"
uci commit network
ifup wg0
```

### nftables（由 fw4 UCI zone 管理，无需手工添加）

wg0 被配置为 vpn zone，fw4 自动生成以下规则：
- `forward_vpn`：允许 wg0 → LAN 转发
- `srcnat_vpn`：wg0 出口 masquerade

持久化文件 `/etc/nftables.d/20-wg-direct.nft` 负责 cn_domains set 和 prerouting mark（见下文）。

---

## 静态路由分流方案

### /usr/local/bin/setup-routes.sh

启动耗时 **<1s**（原方案写入 5000+ 条路由需 ~20s）。

```bash
#!/bin/sh
# 静态路由分流脚本
# 默认走 wg0（翻墙），国内 IP + 必要主机走 eth0.2（直连）
# CN IP 段由 nftset cn_ip 承接，此处只写精确路由（约 15 条）

WAN_IF="eth0.2"
WG_IF="wg0"
WG_ENDPOINT="45.250.184.35"

log() { logger -t "setup-routes" "$*"; }

GW=$(ip route show dev $WAN_IF | awk '/via/{print $3}' | head -1)
[ -z "$GW" ] && { log "no gateway on $WAN_IF, abort"; exit 1; }
log "start: gw=$GW"

# 1. 默认路由走 wg0
ip route replace default dev $WG_IF 2>/dev/null

# 2. WG endpoint 直连（隧道建立必须）
ip route replace $WG_ENDPOINT via $GW dev $WAN_IF 2>/dev/null

# 3. 国内 DNS 直连
for host in 119.29.29.29 114.114.114.114 180.76.76.76; do
    ip route replace $host via $GW dev $WAN_IF 2>/dev/null
done

# 3.5 私有地址段走 eth0.2 直连
for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
    ip route replace $net via $GW dev $WAN_IF 2>/dev/null
done
ip route replace 192.168.254.0/24 dev br-lan 2>/dev/null

# WG 远端专用网段（精确路由覆盖私有大段）
for net in 10.254.0.0/24 10.100.50.0/24 192.168.88.0/23; do
    ip route replace $net dev $WG_IF 2>/dev/null
done

# WG AllowedIPs 中不走 wg0 的段显式覆盖回 eth0.2
for net in 10.100.20.0/25 10.100.89.0/24; do
    ip route replace $net via $GW dev $WAN_IF 2>/dev/null
done

# 4. CN IP 由 nftset cn_ip 承接（update-rules.sh 负责加载），此处无需操作
log "CN IP: handled by nftset cn_ip via update-rules.sh"

# 5. 确保 cn_domains nftset 存在
nft list set inet fw4 cn_domains 2>/dev/null | grep -q "cn_domains" || \
    nft add set inet fw4 cn_domains '{ type ipv4_addr; flags interval; auto-merge; }' 2>/dev/null

# 6. fwmark 0x1 → table 200 → eth0.2 直连
ip rule show | grep -q "fwmark 0x1 lookup 200" || {
    ip rule add fwmark 0x1 table 200 prio 100 2>/dev/null
}
ip route show table 200 | grep -q "default" || {
    ip route add default via $GW dev $WAN_IF table 200 2>/dev/null
}

log "done"
```

### /etc/nftables.d/20-wg-direct.nft（fw4 持久化，重启自动加载）

```nft
# WireGuard 分流持久化规则 - fw4 启动时自动加载

# cn_domains set：SmartDNS 国内域名解析结果动态写入
set cn_domains {
    type ipv4_addr
    flags interval
    auto-merge
}

# cn_ip set：国内 IP 段，由 update-rules.sh 定期加载
set cn_ip {
    type ipv4_addr
    flags interval
    auto-merge
}

# prerouting：命中 cn_domains 或 cn_ip 的包打 mark 0x1，走策略路由 table 200（直连）
chain cn_domains_mark {
    type filter hook prerouting priority mangle - 1
    meta l4proto { tcp, udp } ip daddr @cn_domains meta mark set 0x00000001
    # cn_ip：直接访问国内 IP 时（无域名），同样走直连
    meta l4proto { tcp, udp } ip daddr @cn_ip      meta mark set 0x00000001
}
```

> 部署：`cp 20-wg-direct.nft /etc/nftables.d/` 后执行 `fw4 reload`。

### /etc/hotplug.d/iface/99-wg-route

```bash
#!/bin/sh
[ "$ACTION" = "ifup" ] && [ "$INTERFACE" = "wg0" ] || exit 0
sleep 2
sh /usr/local/bin/setup-routes.sh
# 启动 watchdog（如果未运行）
pgrep -f wg-watchdog.sh >/dev/null || sh /usr/local/bin/wg-watchdog.sh &
```

### /usr/local/bin/wg-watchdog.sh

WG 断线监控，每 30 秒检测一次握手时间，自动 fallback 和恢复路由。

| 参数 | 值 | 说明 |
|------|-----|------|
| 检测方式 | `wg show latest-handshakes` | 直接读内核握手时间戳，不依赖 ICMP |
| 握手超时阈值 | 180s | 等于 WG 协议 REKEY_TIMEOUT，超过才是真正断线 |
| fallback 阈值 | 连续 3 次超时（约 90s）| 防止服务端偶发慢响应误触发 |
| 恢复阈值 | 连续 2 次正常（约 60s）| 防止抖动时来回切换 |
| fallback 动作 | `ip route replace default via $GW dev eth0.2` | 切回直连 |
| 恢复动作 | `sh /usr/local/bin/setup-routes.sh` | 重建完整分流路由 |

```bash
#!/bin/sh
# WG 断线监控：基于握手时间检测，避免 ICMP 误判
# 每 30 秒检测一次，连续 3 次握手超时才 fallback，连续 2 次恢复才切回

WG_IF="wg0"
WAN_IF="eth0.2"
CHECK_INTERVAL=30
WG_STATUS="up"
FAIL_COUNT=0
RECOVER_COUNT=0
FAIL_THRESHOLD=3            # 连续 3 次握手超时才 fallback（约 90s）
RECOVER_THRESHOLD=2         # 连续 2 次握手正常才切回（约 60s）
HANDSHAKE_TIMEOUT=180       # 握手超过 180s 视为断线（等于 WG 协议 REKEY_TIMEOUT，超过才是真正断线）

log() { logger -t "wg-watchdog" "$*"; }

# 获取 WG 对端最后握手距今秒数，失败返回 9999
get_handshake_age() {
    # wg show wg0 latest-handshakes 输出格式：<pubkey>\t<unix_timestamp>
    TS=$(wg show "$WG_IF" latest-handshakes 2>/dev/null | awk '{print $2}' | head -1)
    [ -z "$TS" ] || [ "$TS" = "0" ] && { echo 9999; return; }
    NOW=$(date +%s)
    echo $((NOW - TS))
}

log "watchdog started (handshake-based), threshold=${HANDSHAKE_TIMEOUT}s, check every ${CHECK_INTERVAL}s"

while true; do
    AGE=$(get_handshake_age)
    log "handshake age: ${AGE}s"

    if [ "$AGE" -lt "$HANDSHAKE_TIMEOUT" ]; then
        # 握手正常
        FAIL_COUNT=0
        if [ "$WG_STATUS" = "down" ]; then
            RECOVER_COUNT=$((RECOVER_COUNT + 1))
            log "WG handshake ok, age=${AGE}s ($RECOVER_COUNT/$RECOVER_THRESHOLD), waiting to confirm..."
            if [ "$RECOVER_COUNT" -ge "$RECOVER_THRESHOLD" ]; then
                log "WG recovered, restoring WG routes"
                sh /usr/local/bin/setup-routes.sh
                WG_STATUS="up"
                RECOVER_COUNT=0
            fi
        else
            RECOVER_COUNT=0
        fi
    else
        # 握手超时
        RECOVER_COUNT=0
        if [ "$WG_STATUS" = "up" ]; then
            FAIL_COUNT=$((FAIL_COUNT + 1))
            log "WG handshake stale, age=${AGE}s ($FAIL_COUNT/$FAIL_THRESHOLD)..."
            if [ "$FAIL_COUNT" -ge "$FAIL_THRESHOLD" ]; then
                log "WG down! Falling back to direct connection"
                GW=$(ip route show dev $WAN_IF | awk '/via/{print $3}' | head -1)
                if [ -n "$GW" ]; then
                    ip route replace default via $GW dev $WAN_IF 2>/dev/null
                    log "fallback: default via $GW dev $WAN_IF"
                fi
                WG_STATUS="down"
                FAIL_COUNT=0
            fi
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            log "WG still down, handshake stale age=${AGE}s ($FAIL_COUNT)..."
        fi
    fi

    sleep $CHECK_INTERVAL
done
```

> watchdog 由 hotplug 在 wg0 ifup 时自动启动，无需加入 crontab。

---

## SmartDNS 配置

### DNS 服务器

| 组 | 服务器 | 协议 |
|----|--------|------|
| cn | 119.29.29.29 | UDP（仅 cn 组，-exclude-default-group）|
| cn | 114.114.114.114 | UDP（仅 cn 组，-exclude-default-group）|
| foreign | 8.8.8.8 | UDP（走 WG，-exclude-default-group）|
| foreign | 1.1.1.1 | UDP（走 WG，-exclude-default-group）|
| 默认 | 119.29.29.29 | UDP |
| 默认 | 114.114.114.114 | UDP |

ECS：`edns-client-subnet 202.96.134.0/24`（深圳电信网段，CDN 调度识别为广东电信）

### /etc/smartdns/smartdns.conf

> ⚠️ 此文件**不被 SmartDNS 读取**。SmartDNS 实际运行读取的是 UCI 生成的 `/var/etc/smartdns/smartdns.conf`。上游 DNS 必须通过 `uci set smartdns` 配置，自定义规则在 `/etc/smartdns/custom.conf`。

### UCI server 配置（恢复用）

```bash
# 清空旧配置
while uci -q delete smartdns.@server[0]; do :; done

# 默认组：国内 DNS（直连）
uci add smartdns server
uci set smartdns.@server[-1].name='cn-1'
uci set smartdns.@server[-1].ip='119.29.29.29'
uci set smartdns.@server[-1].type='udp'

uci add smartdns server
uci set smartdns.@server[-1].name='cn-2'
uci set smartdns.@server[-1].ip='114.114.114.114'
uci set smartdns.@server[-1].type='udp'

# foreign 组：国际 DNS（走 wg0，-exclude-default-group）
uci add smartdns server
uci set smartdns.@server[-1].name='foreign-1'
uci set smartdns.@server[-1].ip='8.8.8.8'
uci set smartdns.@server[-1].type='udp'
uci set smartdns.@server[-1].server_group='foreign'
uci set smartdns.@server[-1].exclude_default_group='1'

uci add smartdns server
uci set smartdns.@server[-1].name='foreign-2'
uci set smartdns.@server[-1].ip='1.1.1.1'
uci set smartdns.@server[-1].type='udp'
uci set smartdns.@server[-1].server_group='foreign'
uci set smartdns.@server[-1].exclude_default_group='1'

uci commit smartdns
/etc/init.d/smartdns restart
```

### /etc/smartdns/custom.conf

```
# 国内域名集合 → 解析结果回写到 nftset cn_domains（动态直连）
domain-set -name cn-domains -file /etc/smartdns/rules/cn_domains.txt
nftset /domain-set:cn-domains/#4:inet#fw4#cn_domains

# 微信通话强制国内 DNS（防延迟）
domain-rules /voip.wechat.com/ -nameserver 119.29.29.29 -no-ip-alias
domain-rules /rtc.qq.com/ -nameserver 119.29.29.29 -no-ip-alias
domain-rules /trtc.qq.com/ -nameserver 119.29.29.29 -no-ip-alias

# feishu.cn 及所有子域名强制国内 DNS + 回写 cn_domains（解决冷启动走 wg0 问题）
nftset /.feishu.cn/#4:inet#fw4#cn_domains
domain-rules /.feishu.cn/ -nameserver cn -no-speed-check
# feishu.cn CNAME 链中间域名强制国内 DNS（防止 SmartDNS 选海外节点）
domain-rules /.bytedns1.com/ -nameserver cn -no-speed-check
domain-rules /.kunluncan.com/ -nameserver cn -no-speed-check
nftset /.bytedns1.com/#4:inet#fw4#cn_domains
nftset /.kunluncan.com/#4:inet#fw4#cn_domains
```

### dnsmasq 配置

```bash
# 所有 DNS 转发到 SmartDNS，禁止读取 WAN 推送的上游 DNS
uci set dhcp.@dnsmasq[0].noresolv="1"
uci set dhcp.@dnsmasq[0].resolvfile="/dev/null"
uci set dhcp.@dnsmasq[0].localuse="1"   # 路由器本机查询也走 dnsmasq
uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#5335"
uci commit dhcp
/etc/init.d/dnsmasq restart
```

### WAN 禁止覆盖 DNS（关键）

```bash
# 防止 WAN DHCP 把上游 DNS 写入 /etc/resolv.conf，导致路由器本机无法翻墙
uci set network.wan.peerdns="0"
uci commit network
```

> 正确结果：`cat /etc/resolv.conf` 应显示 `nameserver 127.0.0.1`

---

## 规则更新脚本

### /usr/local/bin/update-rules.sh

每天 03:30 自动更新（含备用镜像源），cn_ip 采用 **diff 增量更新**，避免全量重写导致 OOM。

**下载来源：**
- Loyalsoldier/v2ray-rules-dat：direct-list.txt
- felixonmars/dnsmasq-china-list：accelerated-domains.china.conf
- Loyalsoldier/geoip：cn_ip.txt（~5700 条）

**合并：** cn_domains.txt（~113000 条国内域名）

**cn_ip 更新机制：**
- 首次（无快照）：分批 200 条写入 nftset，峰值内存 <5KB
- 后续：`grep -F -x -v` 做差集，只处理新增/删除条目，通常 <50 条
- 快照文件：`/etc/smartdns/rules/cn_ip.snapshot`

**更新后自动重载：** `pkill -HUP smartdns`（热重载）

**定时任务：**
```
30 3 * * * /usr/local/bin/update-rules.sh
@reboot sleep 180 && /usr/local/bin/update-rules.sh
```

> ⚠️ **注意**：update-rules.sh 每次执行会重新生成 cn_domains.txt，手动追加的域名会丢失。以下域名需在脚本末尾固化追加（cn_domains.txt 上游来源未收录）：
> ```bash
> # 在 update-rules.sh 末尾追加（合并步骤之后）
> grep -q '^feishu\.cn$'    /etc/smartdns/rules/cn_domains.txt || echo 'feishu.cn'    >> /etc/smartdns/rules/cn_domains.txt
> grep -q '^kunluncan\.com$' /etc/smartdns/rules/cn_domains.txt || echo 'kunluncan.com' >> /etc/smartdns/rules/cn_domains.txt
> grep -q '^bytedns1\.com$'  /etc/smartdns/rules/cn_domains.txt || echo 'bytedns1.com'  >> /etc/smartdns/rules/cn_domains.txt
> ```

---

## 已知问题与说明

### 飞书（feishu.cn）冷启动延迟高

**现象**：路由器重启后首次访问 `*.feishu.cn` 速度慢（延迟 150ms+）。

**根因**：
- `feishu.cn` 本身不在上游 cn_domains.txt 中
- SmartDNS 解析 CNAME 链（`feishu.cn → bytedns1.com → kunluncan.com`）时，中间域名追踪走了默认 DNS 上游
- 曾使用 `223.5.5.5`（阿里全球 Anycast），从 WG 出口（香港）查 kunluncan.com 时，CDN 判定为海外请求，返回海外节点（`98.96.242.53`，159ms）

**修复**：
- `custom.conf` 加 `domain-rules /.feishu.cn/ -nameserver cn -no-speed-check` 及 CNAME 链中间域名
- `cn_domains.txt` 手动追加 `feishu.cn` / `kunluncan.com` / `bytedns1.com`
- 修复后飞书全子域名稳定解析到国内节点（10-12ms）

### lark.com 走 wg0（正常现象）

**现象**：`lark.com`（飞书国际版）解析到 `198.202.211.1`，流量走 wg0。

**说明**：`198.202.211.1` 是飞书全球 Anycast 地址（ASN 209242，注册于美国），国内外 DNS 返回同一 IP。从 WG 出口（香港）访问延迟约 11ms，完全可用。如需走直连可将其加入 cn_domains.txt，但效果与现状差异不大。

### WireGuard watchdog 历史问题（已修复）

**现象**：2026-06-09 前，访问 AI 偶发中断（约每 3-5 分钟断一次）。

**根因**：wg-watchdog 用 `ping -c 1 -W 5` 检测，WG 对端 ICMP 偶发超时触发误 fallback，每次中断约 30 秒。

**修复**：改为基于 `wg show latest-handshakes` 握手时间检测，阈值 180s（等于 WG REKEY_TIMEOUT），连续 3 次超时才 fallback。

### SmartDNS 223.5.5.5 导致 CDN 调度异常（已修复）

**现象**：部分国内 CDN 域名（飞书、kunluncan.com 等）解析到海外节点，国内银行 App 无法正常访问。

**根因**：
1. SmartDNS 实际运行读取的是 UCI 生成的 `/var/etc/smartdns/smartdns.conf`，而非 `/etc/smartdns/smartdns.conf`。UCI 生成的配置里原先只有 `server 8.8.8.8`，所有域名（包括国内银行）都用 8.8.8.8 解析，8.8.8.8 经 wg0 出到香港，CDN 判定为海外请求返回海外节点，银行服务器识别到海外来源触发风控
2. 曾使用 `223.5.5.5`（阿里全球 Anycast），从 WG 出口（香港）查 CDN 域名时，同样被调度到海外节点

**修复**：
- 通过 UCI 正确配置上游：默认组 `119.29.29.29` + `114.114.114.114`，foreign 组 `8.8.8.8` + `1.1.1.1`
- `/etc/smartdns/smartdns.conf` 不被读取，加注释说明避免误操作
- ECS `202.96.134.0/24`（深圳电信）写入 custom.conf

**教训**：修改 SmartDNS 上游 DNS 必须用 `uci set smartdns`，不能直接改 `/etc/smartdns/smartdns.conf`。

---

## 性能参数

| 测试 | 结果 |
|------|------|
| LAN 内网吞吐（有线）| 253 Mbps（上行）/ 223 Mbps（下行）|
| WG 翻墙延迟 | ~14ms |
| 国内直连延迟 | ~8-40ms |
| 路由加载时间（nftset 方案）| **<1s**（原 ip route 批量方案约 20s）|
| 路由表条目数 | **~19 条**（原 4000+ 条）|
| cn_ip set 条目 | ~3700 CIDR（nftset 内核哈希匹配）|
| 内存占用（空闲）| ~22MB 可用（128MB 总计，无 swap）|

---

## 重装后恢复流程

### 第一步：基础

```bash
ssh root@192.168.1.1
passwd root          # 输入 Wangke.0912
uci set network.lan.ipaddr="192.168.254.254"
uci commit network
/etc/init.d/network restart
```

### 第二步：SD 卡 extroot

```bash
opkg update
opkg install kmod-phy-ath79-usb kmod-usb2 kmod-usb-storage kmod-scsi-core kmod-fs-ext4 block-mount e2fsprogs
reboot
# 重启后
mkfs.ext4 -L extroot /dev/sda1
block detect > /etc/config/fstab
UUID=$(block info /dev/sda1 | grep -o 'UUID="[^"]*"' | cut -d'"' -f2)
uci set fstab.@mount[0].target="/overlay"
uci set fstab.@mount[0].uuid="$UUID"
uci set fstab.@mount[0].enabled="1"
uci commit fstab
mount /dev/sda1 /mnt && cp -a /overlay/. /mnt/ && umount /mnt
reboot
```

### 第三步：安装软件包

```bash
opkg update
opkg install kmod-wireguard wireguard-tools smartdns \
    ip-full tcpdump mtr bind-dig curl htop iperf3 \
    kmod-fs-vfat kmod-nls-cp437 kmod-nls-iso8859-1
opkg remove dnsmasq-full 2>/dev/null; opkg install dnsmasq
```

### 第四步：配置 WireGuard

按上文 UCI 配置命令执行，然后：

```bash
ifup wg0
wg show   # 确认 handshake 正常
```

### 第五步：配置 DNS（关键，必须在路由脚本前做）

```bash
# 禁止 WAN DHCP 覆盖 resolv.conf
uci set network.wan.peerdns="0"
uci commit network

# dnsmasq 转发到 SmartDNS，路由器本机也走本地 DNS
uci set dhcp.@dnsmasq[0].noresolv="1"
uci set dhcp.@dnsmasq[0].resolvfile="/dev/null"
uci set dhcp.@dnsmasq[0].localuse="1"
uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#5335"
uci commit dhcp

# 配置 SmartDNS 上游 DNS（必须通过 UCI，直接改 /etc/smartdns/smartdns.conf 无效）
while uci -q delete smartdns.@server[0]; do :; done  # 清空旧配置

# 默认组：国内 DNS（直连）
uci add smartdns server
uci set smartdns.@server[-1].name='cn-1'
uci set smartdns.@server[-1].ip='119.29.29.29'
uci set smartdns.@server[-1].type='udp'

uci add smartdns server
uci set smartdns.@server[-1].name='cn-2'
uci set smartdns.@server[-1].ip='114.114.114.114'
uci set smartdns.@server[-1].type='udp'

# foreign 组：国际 DNS（走 wg0，-exclude-default-group）
uci add smartdns server
uci set smartdns.@server[-1].name='foreign-1'
uci set smartdns.@server[-1].ip='8.8.8.8'
uci set smartdns.@server[-1].type='udp'
uci set smartdns.@server[-1].server_group='foreign'
uci set smartdns.@server[-1].exclude_default_group='1'

uci add smartdns server
uci set smartdns.@server[-1].name='foreign-2'
uci set smartdns.@server[-1].ip='1.1.1.1'
uci set smartdns.@server[-1].type='udp'
uci set smartdns.@server[-1].server_group='foreign'
uci set smartdns.@server[-1].exclude_default_group='1'

uci commit smartdns

# 写入 SmartDNS custom.conf（ECS + 自定义规则）
cat > /etc/smartdns/custom.conf << 'EOF'
# ECS：使用深圳电信网段，CDN 调度识别为广东电信
edns-client-subnet 202.96.134.0/24

# 国内域名集合 → 解析结果回写到 nftset cn_domains（动态直连）
domain-set -name cn-domains -file /etc/smartdns/rules/cn_domains.txt
nftset /domain-set:cn-domains/#4:inet#fw4#cn_domains

# 微信通话强制国内 DNS（防延迟）
domain-rules /voip.wechat.com/ -nameserver 119.29.29.29 -no-ip-alias
domain-rules /rtc.qq.com/ -nameserver 119.29.29.29 -no-ip-alias
domain-rules /trtc.qq.com/ -nameserver 119.29.29.29 -no-ip-alias

# feishu.cn 全子域名强制国内 DNS（解决冷启动走 wg0 问题）
nftset /.feishu.cn/#4:inet#fw4#cn_domains
domain-rules /.feishu.cn/ -nameserver cn -no-speed-check
domain-rules /.bytedns1.com/ -nameserver cn -no-speed-check
domain-rules /.kunluncan.com/ -nameserver cn -no-speed-check
nftset /.bytedns1.com/#4:inet#fw4#cn_domains
nftset /.kunluncan.com/#4:inet#fw4#cn_domains
EOF

/etc/init.d/smartdns enable
/etc/init.d/smartdns restart
/etc/init.d/dnsmasq restart
```

### 第六步：部署 nftables 持久化规则

```bash
# 从仓库 .github/scripts/ 拷贝
cp /path/to/repo/.github/scripts/20-wg-direct.nft /etc/nftables.d/
/etc/init.d/firewall reload
```

### 第七步：配置静态路由

```bash
# 从仓库拷贝脚本
cp /path/to/repo/.github/scripts/setup-routes.sh /usr/local/bin/
chmod +x /usr/local/bin/setup-routes.sh
sh /usr/local/bin/setup-routes.sh
```

### 第八步：部署 hotplug 和定时任务

```bash
# hotplug：wg0 up 时自动执行路由脚本并启动 watchdog
cat > /etc/hotplug.d/iface/99-wg-route << 'EOF'
#!/bin/sh
[ "$ACTION" = "ifup" ] && [ "$INTERFACE" = "wg0" ] || exit 0
sleep 2
sh /usr/local/bin/setup-routes.sh
# 启动 watchdog（如果未运行）
pgrep -f wg-watchdog.sh >/dev/null || sh /usr/local/bin/wg-watchdog.sh &
EOF

# 部署 watchdog 脚本
cp /path/to/repo/.github/scripts/wg-watchdog.sh /usr/local/bin/
chmod +x /usr/local/bin/wg-watchdog.sh

# 定时任务
echo "30 3 * * * /usr/local/bin/update-rules.sh" >> /etc/crontabs/root
echo "@reboot sleep 180 && /usr/local/bin/update-rules.sh" >> /etc/crontabs/root
/etc/init.d/cron restart
```

### 第九步：规则更新（首次）

```bash
cp /path/to/repo/.github/scripts/update-rules.sh /usr/local/bin/
chmod +x /usr/local/bin/update-rules.sh
sh /usr/local/bin/update-rules.sh   # 首次执行，下载规则文件
```

### 第十步：WiFi

```bash
uci set wireless.radio0.disabled="0"
uci set wireless.radio0.channel="36"
uci set wireless.radio0.htmode="VHT40"
uci set wireless.radio0.country="CN"
uci set wireless.default_radio0.ssid="Jeff_ar750"
uci set wireless.default_radio0.encryption="psk-mixed"
uci set wireless.default_radio0.key="Wangke.0912"
uci set wireless.radio1.disabled="0"
uci set wireless.radio1.channel="6"
uci set wireless.radio1.htmode="HT20"
uci set wireless.radio1.country="CN"
uci set wireless.default_radio1.ssid="Jeff_ar750"
uci set wireless.default_radio1.encryption="psk-mixed"
uci set wireless.default_radio1.key="Wangke.0912"
uci commit wireless && wifi reload
```

### 第十一步：系统配置

```bash
uci set system.@system[0].hostname="Jeff_AR750S"
uci set system.@system[0].timezone="CST-8"
uci set system.@system[0].zonename="Asia/Shanghai"
uci delete system.ntp.server
uci add_list system.ntp.server="ntp.aliyun.com"
uci add_list system.ntp.server="ntp1.aliyun.com"
uci commit system
```

---

## WAN 切换工具（change_wan）

脚本位于路由器 `/usr/local/bin/change_wan`，可直接 SSH 远程执行。

> **注意**：使用 EAP-PEAP（有线或无线）时，首次执行会自动将 `wpad-basic-mbedtls` 升级为 `wpad-mbedtls`（完整版，支持 802.1X），需要联网。

```bash
# 查看当前状态
ssh root@192.168.254.254 "change_wan status"

# 有线 WAN - DHCP
ssh root@192.168.254.254 "change_wan eth"

# 有线 WAN - 静态 IP（mask 默认 255.255.255.0）
ssh root@192.168.254.254 "change_wan eth proto=static ip=10.99.57.66 gw=10.99.57.253"
ssh root@192.168.254.254 "change_wan eth proto=static ip=10.99.57.66 gw=10.99.57.253 mask=255.255.255.0"

# 有线 WAN - DHCP + EAP-PEAP 企业认证（802.1X 有线）
ssh root@192.168.254.254 "change_wan eth eap=peap identity=user@corp.com pwd=MyPass"

# 有线 WAN - 静态 IP + EAP-PEAP
ssh root@192.168.254.254 "change_wan eth proto=static ip=x.x.x.x gw=x.x.x.x eap=peap identity=user@corp.com pwd=MyPass"

# 无线 WAN - WPA2-PSK，DHCP，5GHz（默认）
ssh root@192.168.254.254 "change_wan wifi ssid=MyWiFi pwd=MyPass"

# 无线 WAN - WPA2-PSK，DHCP，2.4GHz
ssh root@192.168.254.254 "change_wan wifi ssid=MyWiFi pwd=MyPass band=2g"

# 无线 WAN - EAP-PEAP 企业认证（802.1X 无线），DHCP
ssh root@192.168.254.254 "change_wan wifi ssid=CorpWiFi eap=peap identity=user@corp.com pwd=MyPass"
ssh root@192.168.254.254 "change_wan wifi ssid=CorpWiFi eap=peap identity=user@corp.com pwd=MyPass band=2g"

# 从无线切回有线
ssh root@192.168.254.254 "change_wan eth"
```

切换完成后自动重建路由（调用 `setup-routes.sh`），WG 隧道不受影响。

---



```bash
# WG 状态
wg show

# 验证路由分流
ip route get 8.8.8.8       # 应走 wg0
ip route get 119.29.29.29  # 应走 eth0.2
ip route get 36.152.44.95  # 百度，应走 eth0.2（命中 cn_ip nftset）

# 路由表（应只有约 20 条精确路由）
ip route show | wc -l

# 策略路由
ip rule show               # 应有 fwmark 0x1 lookup 200
ip route show table 200    # 应有 default via 上游网关

# nftset 状态
nft list set inet fw4 cn_ip     | grep -oE '[0-9.]+/[0-9]+' | wc -l  # CN IP 条目数
nft list set inet fw4 cn_domains | grep -oE '[0-9.]+' | wc -l         # 动态域名 IP 条目数

# nft 分流规则确认
nft list chain inet fw4 cn_domains_mark

# cn_ip 快照文件（增量更新基准）
ls -lh /etc/smartdns/rules/cn_ip.snapshot

# 出口 IP（应为 WG 服务器 IP）
curl -s https://api.ipify.org

# DNS 测试
dig google.com @127.0.0.1 -p 5335 +short   # 应返回境外 IP
dig baidu.com @127.0.0.1 -p 5335 +short    # 应返回国内 IP

# resolv.conf（应为 127.0.0.1）
cat /etc/resolv.conf

# 内存
free -m

# SD 卡
df -h /overlay
```

---

## 版本记录

| 日期 | 变更 |
|------|------|
| 2026-06-05 | 初始部署，WG + SmartDNS |
| 2026-06-05 | 翻墙方案改为静态路由分流（最简方式）|
| 2026-06-05 | 修复 wg0 masquerade 和 forward 转发规则 |
| 2026-06-05 | 补充 SmartDNS nftset 动态回写（cn_domains）；修复路由器本机 DNS（peerdns=0 + localuse=1）；nftables 持久化到 /etc/nftables.d/20-wg-direct.nft；setup-routes.sh 国内 DNS 路由补 via $GW |
| 2026-06-05 | 私有地址段（10/8、172.16/12、192.168/16）全部走 eth0.2 直连；WG 专用段精确覆盖为 10.254.0.0/24、10.100.50.0/24、192.168.88.0/23；显式覆盖 AllowedIPs 中不走 WG 的段（10.100.20.0/25、10.100.89.0/24）|
| 2026-06-05 | WAN 改为静态 IP（10.99.57.66，网关 10.99.57.253）；change_wan 支持 proto=static/dhcp、ip=、gw=、mask= 参数，eth 和 wifi 模式均支持 |
| 2026-06-05 | 所有私有段（10/8、172.16/12、192.168/16）改走 eth0.2 直连；WG 远端内网精确段覆盖回 wg0 |
| 2026-06-08 | **重构分流方案**：CN IP 段由 5000+ 条 ip route 改为 nftset cn_ip（~3700 CIDR），setup-routes.sh 启动时间从 ~20s 降到 <1s，路由表从 4000+ 条降到 ~19 条 |
| 2026-06-08 | **新增 nftset cn_ip**：20-wg-direct.nft 增加 cn_ip set 定义及 prerouting mark 规则，与 cn_domains 统一走 fwmark 0x1 → table 200 直连 |
| 2026-06-08 | **update-rules.sh 改为 diff 增量更新**：首次全量分批写入（200条/批），后续只处理新增/删除差集，OOM 风险消除；使用快照文件 cn_ip.snapshot 作为基准 |
| 2026-06-09 | **wg-watchdog 重构**：检测方式从 `ping -c 1 -W 5` 改为 `wg show latest-handshakes` 握手时间检测，彻底消除 ICMP 误判；新增连续失败计数器（3次/90s 才 fallback）和恢复计数器（2次/60s 才切回），防止路由来回抖动；握手超时阈值从 120s 调整为 180s（等于 WG 协议 REKEY_TIMEOUT），消除误触发余量不足的问题 |
| 2026-06-09 | **SmartDNS 优化**：国内 DNS 组改为 119.29.29.29 + 114.114.114.114（去掉 223.5.5.5）；国外组 8.8.8.8 + 1.1.1.1；新增 ECS `202.96.134.0/24`（深圳电信）解决 CDN 调度选海外节点问题；custom.conf 新增 feishu.cn 全子域名强制国内 DNS + cn_domains 回写，修复冷启动后飞书走 wg0 延迟高的问题 |
| 2026-06-09 | **SmartDNS DNS 上游修复（根本原因）**：发现 SmartDNS 实际读取 `/var/etc/smartdns/smartdns.conf`（UCI 生成），而非 `/etc/smartdns/smartdns.conf`；UCI 原配置只有 `server 8.8.8.8` 导致所有域名走海外 DNS，国内银行 App 无法访问；通过 UCI 重新配置：默认组 `119.29.29.29` + `114.114.114.114`，foreign 组 `8.8.8.8` + `1.1.1.1`，多余的 `8.8.4.4`/`1.0.0.1`/`223.5.5.5` 全部清除；`/etc/smartdns/smartdns.conf` 加注释标注不生效，避免误导 |
