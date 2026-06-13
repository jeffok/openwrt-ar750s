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
