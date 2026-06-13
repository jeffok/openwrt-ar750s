#!/bin/sh
# 静态路由分流脚本
# 默认走 wg0（翻墙），国内 IP + 必要主机走 eth0.2（直连）
# 同时创建 cn_domains nftset（供 SmartDNS 回写动态直连 IP）

WAN_IF="eth0.2"
WG_IF="wg0"
WG_ENDPOINT="45.250.184.35"

log() { logger -t "setup-routes" "$*"; }

# 获取 eth0.2 的网关（DHCP 动态，每次可能不同）
GW=$(ip route show dev $WAN_IF | awk '/via/{print $3}' | head -1)
[ -z "$GW" ] && { log "no gateway on $WAN_IF, abort"; exit 1; }
log "start: gw=$GW"

# 1. 默认路由走 wg0（全局翻墙）
ip route replace default dev $WG_IF 2>/dev/null

# 2. WG endpoint 必须直连（否则隧道无法建立）
ip route replace $WG_ENDPOINT via $GW dev $WAN_IF 2>/dev/null

# 3. 国内 DNS 直连（必须带 via $GW，否则部分内核报错）
for host in 119.29.29.29 223.5.5.5 114.114.114.114 180.76.76.76; do
    ip route replace $host via $GW dev $WAN_IF 2>/dev/null
done

# 3.5 所有私有地址段走 eth0.2 直连（内网访问不走 WG）
for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
    ip route replace $net via $GW dev $WAN_IF 2>/dev/null
done
# 本机 LAN 段保持 kernel 路由，覆盖上面的 192.168.0.0/16 大段
ip route replace 192.168.254.0/24 dev br-lan 2>/dev/null

# WG 远端专用网段（精确路由覆盖上面的私有大段，确保走 wg0）
# 如需新增 WG 网段，在此列表追加即可
for net in 10.254.0.0/24 10.100.50.0/24 192.168.88.0/23; do
    ip route replace $net dev $WG_IF 2>/dev/null
done
log "WG private nets routed via $WG_IF: 10.254.0.0/24 10.100.50.0/24 192.168.88.0/23"

# WG AllowedIPs 中不需要走 wg0 的网段，显式覆盖回 eth0.2
# （WG 内核会为 AllowedIPs 自动加路由，精确段优先级高于大段，必须逐一覆盖）
for net in 10.100.20.0/25 10.100.89.0/24; do
    ip route replace $net via $GW dev $WAN_IF 2>/dev/null
done
log "WG AllowedIPs non-WG nets forced to $WAN_IF: 10.100.20.0/25 10.100.89.0/24"

# 4. CN IP 由 nftset cn_ip 承接（update-rules.sh 负责加载），此处无需操作
log "CN IP: handled by nftset cn_ip via update-rules.sh"

# 5. 创建 cn_domains nftset（SmartDNS 国内域名解析 IP 回写到此 set）
#    interval + auto-merge 允许写入 CIDR，避免重复
nft list set inet fw4 cn_domains 2>/dev/null | grep -q "cn_domains" || \
    nft add set inet fw4 cn_domains '{ type ipv4_addr; flags interval; auto-merge; }' 2>/dev/null && \
    log "nftset cn_domains ready"

# 6. cn_domains set 的流量走直连（prerouting 打 mark 0x1，然后查 table 200）
#    table 200 只有一条默认路由走 eth0.2
ip rule show | grep -q "fwmark 0x1 lookup 200" || {
    ip rule add fwmark 0x1 table 200 prio 100 2>/dev/null
    log "ip rule fwmark 0x1 -> table 200 added"
}
ip route show table 200 | grep -q "default" || {
    ip route add default via $GW dev $WAN_IF table 200 2>/dev/null
    log "table 200 default via $GW added"
}

# 7. prerouting mark 规则由 /etc/nftables.d/20-wg-direct.nft 持久化，此处只确认 ip rule/table
# nftables.d 由 fw4 启动时加载，无需在此重复添加

# 8. nftables wg0 forward/masquerade 已由 fw4 UCI zone 配置管理，无需手工添加

log "done"
