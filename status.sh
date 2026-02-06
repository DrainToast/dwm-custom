#!/bin/bash
# Optimized Status2D for dwm
# CPU, RAM, GPU, Network, Disk usage, Time
# Single sleep per loop

BG="#3c3836"
FG="#ebdbb2"
PAD=3
COLOR_LOW="#b8bb26"    # green
COLOR_MID="#fabd2f"    # yellow
COLOR_HIGH="#fb4934"   # red

# --- Helper functions ---
pad() { printf "%*s" "$1" ""; }

hex_to_rgb() { printf "%d %d %d" "$((16#${1:1:2}))" "$((16#${1:3:2}))" "$((16#${1:5:2}))"; }
rgb_to_hex() { printf "#%02x%02x%02x" "$1" "$2" "$3"; }

lerp() { echo "$(( $1 + ($2 - $1) * $3 / 100 ))"; }

heat_color() {
    local P=$1 R G B R1 G1 B1 R2 G2 B2 t
    if [ "$P" -le 50 ]; then
        t=$(( P * 2 ))
        read R1 G1 B1 <<< "$(hex_to_rgb "$COLOR_LOW")"
        read R2 G2 B2 <<< "$(hex_to_rgb "$COLOR_MID")"
    else
        t=$(( (P-50) * 2 ))
        read R1 G1 B1 <<< "$(hex_to_rgb "$COLOR_MID")"
        read R2 G2 B2 <<< "$(hex_to_rgb "$COLOR_HIGH")"
    fi
    R=$(lerp "$R1" "$R2" "$t")
    G=$(lerp "$G1" "$G2" "$t")
    B=$(lerp "$B1" "$B2" "$t")
    rgb_to_hex "$R" "$G" "$B"
}

# --- Initial snapshots ---
read _ user nice system idle iowait irq softirq steal _ _ < /proc/stat
CPU_TOTAL_PREV=$((user + nice + system + idle + iowait + irq + softirq + steal))
CPU_IDLE_PREV=$((idle + iowait))

NETIF=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {print $5; exit}')
[ -z "$NETIF" ] && NETIF="lo"   # fallback

RX_PREV=$(cat /sys/class/net/"$NETIF"/statistics/rx_bytes 2>/dev/null || echo 0)
TX_PREV=$(cat /sys/class/net/"$NETIF"/statistics/tx_bytes 2>/dev/null || echo 0)

# --- Main loop ---
while true; do
    # --- CPU ---
    read _ user nice system idle iowait irq softirq steal _ _ < /proc/stat
    CPU_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
    CPU_IDLE=$((idle + iowait))
    TOTAL_DIFF=$((CPU_TOTAL - CPU_TOTAL_PREV))
    IDLE_DIFF=$((CPU_IDLE - CPU_IDLE_PREV))

    if [ "$TOTAL_DIFF" -gt 0 ]; then
        CPU_PERCENT=$(( 100 * (TOTAL_DIFF - IDLE_DIFF) / TOTAL_DIFF ))
    else
        CPU_PERCENT=0
    fi

    CPU_COLOR=$(heat_color "$CPU_PERCENT")
    CPU_STR="^c$CPU_COLOR^CPU: ${CPU_PERCENT}%^d^"
    CPU_TOTAL_PREV=$CPU_TOTAL
    CPU_IDLE_PREV=$CPU_IDLE

    # --- RAM ---
    MEM_PERCENT=$(awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {printf "%.0f", (t-a)/t*100}' /proc/meminfo)
    MEM_COLOR=$(heat_color "$MEM_PERCENT")
    MEM_STR="^c$MEM_COLOR^RAM: ${MEM_PERCENT}%^d^"

    # --- GPU ---
    if command -v nvidia-smi >/dev/null 2>&1; then
        GPU_PERCENT=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null || echo "0")
        GPU_COLOR=$(heat_color "$GPU_PERCENT")
        GPU_STR="^c$GPU_COLOR^GPU: ${GPU_PERCENT}%^d^"
    else
        GPU_STR="^c$FG^GPU: N/A^d^"
    fi

    # --- Network (improved) ---
    RX_CUR=$(cat /sys/class/net/"$NETIF"/statistics/rx_bytes 2>/dev/null || echo 0)
    TX_CUR=$(cat /sys/class/net/"$NETIF"/statistics/tx_bytes 2>/dev/null || echo 0)

    if [ "$RX_PREV" -eq 0 ] && [ "$TX_PREV" -eq 0 ]; then
        RX_RATE=0
        TX_RATE=0
    else
        RX_RATE=$(( (RX_CUR - RX_PREV) / 1024 ))
        TX_RATE=$(( (TX_CUR - TX_PREV) / 1024 ))
    fi

    [ "$RX_RATE" -lt 0 ] && RX_RATE=0
    [ "$TX_RATE" -lt 0 ] && TX_RATE=0

    RX_PREV=$RX_CUR
    TX_PREV=$TX_CUR

    # Auto K/M units
    if [ "$RX_RATE" -ge 1000 ]; then RX_DISP=$(awk "BEGIN {printf \"%.1f\", $RX_RATE/1000}")M; else RX_DISP="${RX_RATE}K"; fi
    if [ "$TX_RATE" -ge 1000 ]; then TX_DISP=$(awk "BEGIN {printf \"%.1f\", $TX_RATE/1000}")M; else TX_DISP="${TX_RATE}K"; fi

    NET_STR="^c$FG^NET: ${RX_DISP}↓ ${TX_DISP}↑^d^"

    # --- Disk usage ---
    DISK_USAGE_PERCENT=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
    DISK_COLOR=$(heat_color "$DISK_USAGE_PERCENT")
    DISK_STR="^c$DISK_COLOR^DISK: ${DISK_USAGE_PERCENT}%^d^"

    # --- Time ---
    TIME_STR="^c$FG^$(date '+%Y-%m-%d %H:%M')^d^"

    # --- Build & set status ---
    PADDING=$(pad "$PAD")
    STATUS="${CPU_STR}${PADDING}${MEM_STR}${PADDING}${GPU_STR}${PADDING}${DISK_STR}${PADDING}${NET_STR}${PADDING}${TIME_STR}${PADDING}"
    xsetroot -name "$STATUS"

    sleep 0.3
done
