#!/bin/sh
# SmartDNS + nftables 规则更新脚本
# 融合 Loyalsoldier + felixonmars 国内域名列表 + CN IP
RULES_DIR=/etc/smartdns/rules
LOG_TAG=update-rules
log() { logger -t "$LOG_TAG" "$*"; echo "$(date +%H:%M:%S) $*"; }
CHANGED=0

dl() {
    name="$1"; url="$2"; out="$RULES_DIR/$name"; tmp="$out.tmp"
    for src in "$url" "https://gh-proxy.com/$url" "https://ghfast.top/$url"; do
        curl -sSL --connect-timeout 10 --max-time 60 -o "$tmp" "$src" 2>/dev/null
        if [ -s "$tmp" ]; then
            if [ -f "$out" ] && cmp -s "$out" "$tmp"; then
                log "= $name (unchanged)"
            else
                mv -f "$tmp" "$out"
                log "OK $name ($(wc -l < "$out") lines)"
                CHANGED=1
            fi
            rm -f "$tmp"
            return 0
        fi
        rm -f "$tmp"
    done
    if [ -f "$out" ] && [ -s "$out" ]; then
        log "WARN $name all sources failed, kept local"
    else
        log "FAIL $name no local copy"
    fi
    return 0
}

log "=== start update ==="

dl direct-list.txt "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/direct-list.txt"
dl accelerated-domains.china.conf "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf"
dl apple.china.conf "https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/apple.china.conf"
dl gfw.txt "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt"
dl cn_ip.txt "https://raw.githubusercontent.com/Loyalsoldier/geoip/release/text/cn.txt"

log "merging cn_domains..."
{
    grep -v "^#" "$RULES_DIR/direct-list.txt" 2>/dev/null | grep -vE "^$|^full:|^regexp:"
    awk -F/ '/^server=/{print $2}' "$RULES_DIR/accelerated-domains.china.conf" 2>/dev/null
    awk -F/ '/^server=/{print $2}' "$RULES_DIR/apple.china.conf" 2>/dev/null
} | sort -u > "$RULES_DIR/cn_domains.txt.tmp"

L=$(wc -l < "$RULES_DIR/cn_domains.txt.tmp")
if [ "$L" -gt 1000 ]; then
    if [ -f "$RULES_DIR/cn_domains.txt" ] && cmp -s "$RULES_DIR/cn_domains.txt" "$RULES_DIR/cn_domains.txt.tmp"; then
        log "= cn_domains.txt (unchanged, $L lines)"
        rm -f "$RULES_DIR/cn_domains.txt.tmp"
    else
        mv -f "$RULES_DIR/cn_domains.txt.tmp" "$RULES_DIR/cn_domains.txt"
        log "OK cn_domains.txt ($L lines)"
        CHANGED=1
    fi
else
    log "FAIL cn_domains too small ($L lines)"
    rm -f "$RULES_DIR/cn_domains.txt.tmp"
fi

if [ -f "$RULES_DIR/cn_ip.txt" ] && [ -s "$RULES_DIR/cn_ip.txt" ]; then
    IL=$(wc -l < "$RULES_DIR/cn_ip.txt")
    if [ "$IL" -gt 1000 ]; then
        # 确保 set 存在（fw4 重启前可能未加载 nft 文件）
        nft list set inet fw4 cn_ip >/dev/null 2>&1 || \
            nft add set inet fw4 cn_ip '{ type ipv4_addr; flags interval; auto-merge; }' 2>/dev/null

        SNAPSHOT="$RULES_DIR/cn_ip.snapshot"
        NEW_SORTED="/tmp/cn_ip_new.txt"
        # 仅取 IPv4 条目（过滤掉 IPv6），排序后存临时文件
        grep -v ":" "$RULES_DIR/cn_ip.txt" | sort > "$NEW_SORTED"

        # 分批写入辅助函数（每批 200 条，避免单条命令过长导致 OOM）
        nft_batch_add() {
            awk 'BEGIN{b="";c=0}{b=(b=="")?$1:b", "$1;c++;if(c>=200){print "add element inet fw4 cn_ip { "b" }";b="";c=0}}END{if(c>0)print "add element inet fw4 cn_ip { "b" }"}' | \
            while IFS= read -r cmd; do nft "$cmd" 2>/dev/null; done
        }
        nft_batch_del() {
            awk 'BEGIN{b="";c=0}{b=(b=="")?$1:b", "$1;c++;if(c>=200){print "delete element inet fw4 cn_ip { "b" }";b="";c=0}}END{if(c>0)print "delete element inet fw4 cn_ip { "b" }"}' | \
            while IFS= read -r cmd; do nft "$cmd" 2>/dev/null; done
        }

        if [ ! -f "$SNAPSHOT" ]; then
            # 无快照：首次全量分批加载
            log "cn_ip set: no snapshot, full load in batches..."
            nft flush set inet fw4 cn_ip 2>/dev/null
            nft_batch_add < "$NEW_SORTED"
            cp "$NEW_SORTED" "$SNAPSHOT"
            log "OK cn_ip full load done ($(wc -l < "$SNAPSHOT") entries)"
            CHANGED=1
        else
            # 有快照：diff 增量更新，临时文件做差集（busybox ash 兼容）
            ADDED="/tmp/cn_ip_added.txt"
            REMOVED="/tmp/cn_ip_removed.txt"
            # 新增：在 NEW 不在 SNAPSHOT
            grep -F -x -v -f "$SNAPSHOT" "$NEW_SORTED" > "$ADDED"
            # 删除：在 SNAPSHOT 不在 NEW
            grep -F -x -v -f "$NEW_SORTED" "$SNAPSHOT" > "$REMOVED"

            ADD_COUNT=$(wc -l < "$ADDED")
            DEL_COUNT=$(wc -l < "$REMOVED")

            if [ "$ADD_COUNT" -eq 0 ] && [ "$DEL_COUNT" -eq 0 ]; then
                log "= cn_ip set (unchanged)"
            else
                log "cn_ip set diff: +$ADD_COUNT -$DEL_COUNT entries"
                [ "$ADD_COUNT" -gt 0 ] && nft_batch_add < "$ADDED"
                [ "$DEL_COUNT" -gt 0 ] && nft_batch_del < "$REMOVED"
                cp "$NEW_SORTED" "$SNAPSHOT"
                log "OK cn_ip diff applied (+$ADD_COUNT -$DEL_COUNT)"
                CHANGED=1
            fi
            rm -f "$ADDED" "$REMOVED"
        fi
        rm -f "$NEW_SORTED"
    fi
fi

if [ "$CHANGED" = "1" ]; then
    if pgrep smartdns >/dev/null 2>&1; then
        pkill -HUP smartdns 2>/dev/null && log "OK smartdns reloaded" || {
            /etc/init.d/smartdns restart
            log "OK smartdns restarted"
        }
    else
        log "smartdns not running, skip reload"
    fi
else
    log "no changes, skip reload"
fi

log "=== done ==="
