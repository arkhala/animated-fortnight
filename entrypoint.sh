#!/bin/sh
set -e

#═══════════════════════════════════════════════════════════════════
# TORWARE MINIMAL - Unattended Tor Relay + Snowflake for Flux Cloud
#═══════════════════════════════════════════════════════════════════

# Configuration from environment
MODE="${MODE:-bridge}"                    # bridge, middle, exit, snowflake, bridge+snowflake
NICKNAME="${NICKNAME:-FluxTorRelay}"
CONTACT="${CONTACT:-}"
BANDWIDTH="${BANDWIDTH:-5}"               # Mbit/s
ORPORT="${ORPORT:-9001}"
OBFS4PORT="${OBFS4PORT:-9002}"
SNOWFLAKE_CAPACITY="${SNOWFLAKE_CAPACITY:-10}"
STATS_INTERVAL="${STATS_INTERVAL:-300}"   # Stats every 5 minutes
DATA_DIR="${DATA_DIR:-/data}"

# Derived values
BW_BYTES=$((BANDWIDTH * 125000))
BW_BURST=$((BW_BYTES * 2))

# Logging
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log_stats() { echo "[STATS $(date '+%Y-%m-%d %H:%M:%S')] $*"; }

#───────────────────────────────────────────────────────────────────
# Generate Tor configuration
#───────────────────────────────────────────────────────────────────
generate_torrc() {
    local torrc="${DATA_DIR}/torrc"
    
    log "Generating torrc for mode: ${MODE}"
    
    cat > "$torrc" << EOF
# Torware Minimal - Auto-generated
# Mode: ${MODE}
# Generated: $(date -Iseconds)

DataDirectory ${DATA_DIR}/tor
User tor

# Logging
Log notice stdout

# Network
ORPort ${ORPORT}
SocksPort 0

# Bandwidth (${BANDWIDTH} Mbit/s)
RelayBandwidthRate ${BW_BYTES}
RelayBandwidthBurst ${BW_BURST}

# Identity
Nickname ${NICKNAME}
EOF

    [ -n "$CONTACT" ] && echo "ContactInfo ${CONTACT}" >> "$torrc"

    # Mode-specific configuration
    case "$MODE" in
        bridge|bridge+snowflake)
            cat >> "$torrc" << EOF

# Bridge Configuration (obfs4)
BridgeRelay 1
ServerTransportPlugin obfs4 exec /usr/bin/obfs4proxy
ServerTransportListenAddr obfs4 0.0.0.0:${OBFS4PORT}
ExtORPort auto
PublishServerDescriptor bridge

# Bridge does not need exit policy but set anyway
ExitPolicy reject *:*
EOF
            ;;
        middle)
            cat >> "$torrc" << EOF

# Middle Relay Configuration
ExitRelay 0
ExitPolicy reject *:*
PublishServerDescriptor 1
EOF
            ;;
        exit)
            cat >> "$torrc" << EOF

# Exit Relay - Reduced Policy (web only)
ExitPolicy accept *:80
ExitPolicy accept *:443
ExitPolicy reject *:*
PublishServerDescriptor 1
EOF
            ;;
        snowflake)
            # Snowflake-only mode, no Tor relay
            log "Snowflake-only mode, skipping Tor relay"
            return 1
            ;;
    esac

    # Ensure data directory exists
    mkdir -p "${DATA_DIR}/tor"
    chown -R tor:tor "${DATA_DIR}/tor"
    chmod 700 "${DATA_DIR}/tor"
    
    return 0
}

#───────────────────────────────────────────────────────────────────
# Stats collection and logging
#───────────────────────────────────────────────────────────────────
collect_tor_stats() {
    local data_dir="${DATA_DIR}/tor"
    
    # Check if Tor is running
    if ! pgrep -x tor > /dev/null 2>&1; then
        return
    fi
    
    # Get fingerprint
    local fingerprint=""
    if [ -f "${data_dir}/fingerprint" ]; then
        fingerprint=$(cat "${data_dir}/fingerprint" 2>/dev/null | awk '{print $2}')
    fi
    
    # Get bridge line for bridges
    local bridge_line=""
    if [ "$MODE" = "bridge" ] || [ "$MODE" = "bridge+snowflake" ]; then
        if [ -f "${data_dir}/pt_state/obfs4_bridgeline.txt" ]; then
            bridge_line=$(grep -v '^#' "${data_dir}/pt_state/obfs4_bridgeline.txt" 2>/dev/null | head -1)
        fi
    fi
    
    # Traffic stats from Tor state
    local written=0 read_bytes=0
    if [ -f "${data_dir}/state" ]; then
        written=$(grep -E "^TotalBytesWritten " "${data_dir}/state" 2>/dev/null | awk '{print $2}' || echo 0)
        read_bytes=$(grep -E "^TotalBytesRead " "${data_dir}/state" 2>/dev/null | awk '{print $2}' || echo 0)
    fi
    
    # Format bytes
    format_bytes() {
        local bytes=$1
        if [ "$bytes" -ge 1073741824 ]; then
            echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}") GB"
        elif [ "$bytes" -ge 1048576 ]; then
            echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}") MB"
        elif [ "$bytes" -ge 1024 ]; then
            echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1024}") KB"
        else
            echo "${bytes} B"
        fi
    }
    
    # Log stats
    log_stats "=== TOR RELAY STATS ==="
    log_stats "Mode: ${MODE}"
    log_stats "Nickname: ${NICKNAME}"
    [ -n "$fingerprint" ] && log_stats "Fingerprint: ${fingerprint}"
    log_stats "Traffic: ↓ $(format_bytes ${read_bytes:-0}) | ↑ $(format_bytes ${written:-0})"
    log_stats "Bandwidth limit: ${BANDWIDTH} Mbit/s"
    
    if [ -n "$bridge_line" ]; then
        log_stats "Bridge line: ${bridge_line}"
    fi
}

collect_snowflake_stats() {
    # Get Snowflake metrics if running
    if ! pgrep -f snowflake-proxy > /dev/null 2>&1; then
        return
    fi
    
    local metrics=$(curl -s --max-time 5 http://127.0.0.1:9999/metrics 2>/dev/null || echo "")
    
    if [ -n "$metrics" ]; then
        local connections=$(echo "$metrics" | grep -E '^snowflake_proxy_client_connections_total' | awk '{print $2}' | head -1 || echo "0")
        local bytes_in=$(echo "$metrics" | grep -E '^snowflake_proxy_client_bytes_received_total' | awk '{print $2}' | head -1 || echo "0")
        local bytes_out=$(echo "$metrics" | grep -E '^snowflake_proxy_client_bytes_sent_total' | awk '{print $2}' | head -1 || echo "0")
        
        # Format bytes
        format_bytes() {
            local bytes=$1
            bytes=${bytes%.*}  # Remove decimal
            if [ "${bytes:-0}" -ge 1073741824 ]; then
                echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}") GB"
            elif [ "${bytes:-0}" -ge 1048576 ]; then
                echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}") MB"
            elif [ "${bytes:-0}" -ge 1024 ]; then
                echo "$(awk "BEGIN {printf \"%.1f\", $bytes/1024}") KB"
            else
                echo "${bytes:-0} B"
            fi
        }
        
        log_stats "=== SNOWFLAKE PROXY STATS ==="
        log_stats "Total connections: ${connections%.*}"
        log_stats "Traffic: ↓ $(format_bytes ${bytes_in:-0}) | ↑ $(format_bytes ${bytes_out:-0})"
    fi
}

stats_loop() {
    while true; do
        sleep "${STATS_INTERVAL}"
        log_stats "────────────────────────────────────────"
        collect_tor_stats
        collect_snowflake_stats
        log_stats "────────────────────────────────────────"
    done
}

#───────────────────────────────────────────────────────────────────
# Process management
#───────────────────────────────────────────────────────────────────
start_tor() {
    if generate_torrc; then
        log "Starting Tor relay..."
        tor -f "${DATA_DIR}/torrc" &
        TOR_PID=$!
        log "Tor started with PID ${TOR_PID}"
    fi
}

start_snowflake() {
    log "Starting Snowflake proxy (capacity: ${SNOWFLAKE_CAPACITY})..."
    /usr/local/bin/snowflake-proxy \
        -capacity "${SNOWFLAKE_CAPACITY}" \
        -metrics \
        -metrics-port 9999 \
        2>&1 | while read -r line; do
            echo "[SNOWFLAKE] $line"
        done &
    SNOWFLAKE_PID=$!
    log "Snowflake started with PID ${SNOWFLAKE_PID}"
}

cleanup() {
    log "Shutting down..."
    [ -n "$TOR_PID" ] && kill "$TOR_PID" 2>/dev/null
    [ -n "$SNOWFLAKE_PID" ] && kill "$SNOWFLAKE_PID" 2>/dev/null
    [ -n "$STATS_PID" ] && kill "$STATS_PID" 2>/dev/null
    wait
    log "Shutdown complete"
    exit 0
}

#───────────────────────────────────────────────────────────────────
# Main
#───────────────────────────────────────────────────────────────────
main() {
    trap cleanup SIGTERM SIGINT
    
    log "╔═══════════════════════════════════════════════════════════╗"
    log "║           TORWARE MINIMAL - Flux Cloud Edition            ║"
    log "╠═══════════════════════════════════════════════════════════╣"
    log "║  Mode:      ${MODE}"
    log "║  Nickname:  ${NICKNAME}"
    log "║  Bandwidth: ${BANDWIDTH} Mbit/s"
    log "║  ORPort:    ${ORPORT}"
    [ "$MODE" = "bridge" ] || [ "$MODE" = "bridge+snowflake" ] && \
    log "║  obfs4Port: ${OBFS4PORT}"
    log "║  Stats:     every ${STATS_INTERVAL}s"
    log "╚═══════════════════════════════════════════════════════════╝"
    
    # Ensure data directory
    mkdir -p "${DATA_DIR}"
    chown -R tor:tor "${DATA_DIR}"
    
    # Start services based on mode
    case "$MODE" in
        bridge|middle|exit)
            start_tor
            ;;
        snowflake)
            start_snowflake
            ;;
        bridge+snowflake)
            start_tor
            sleep 2
            start_snowflake
            ;;
        *)
            log "ERROR: Unknown mode '${MODE}'"
            log "Valid modes: bridge, middle, exit, snowflake, bridge+snowflake"
            exit 1
            ;;
    esac
    
    # Start stats collection in background
    stats_loop &
    STATS_PID=$!
    
    # Wait for any process to exit
    wait -n 2>/dev/null || wait
    
    log "A process exited unexpectedly, shutting down..."
    cleanup
}

# Handle commands
case "${1:-start}" in
    start)
        main
        ;;
    health)
        # Simple health check
        if [ "$MODE" = "snowflake" ]; then
            pgrep -f snowflake-proxy > /dev/null && echo "healthy" && exit 0
        else
            pgrep -x tor > /dev/null && echo "healthy" && exit 0
        fi
        echo "unhealthy"
        exit 1
        ;;
    stats)
        collect_tor_stats
        collect_snowflake_stats
        ;;
    *)
        exec "$@"
        ;;
esac
