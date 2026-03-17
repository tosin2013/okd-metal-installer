#!/bin/bash
# OKD-Metal Discovery Agent
# Embedded into CoreOS live ISO via coreos-installer iso customize --post-install
# Runs after coreos-installer completes disk installation
#
# This script:
# 1. Collects hardware telemetry
# 2. Phones home to the provisioning host
# 3. Logs installation completion
#
# The actual disk installation (coreos-installer install) and Ignition
# application are handled by coreos-installer's --dest-device and
# --dest-ignition flags, not by this script.

set -euo pipefail

LOGFILE="/var/log/okd-metal-discovery.log"

log() {
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "$LOGFILE"
}

collect_hardware_info() {
    log "=== Hardware Telemetry ==="

    log "Hostname: $(hostname)"

    log "MAC addresses:"
    for iface in /sys/class/net/*/address; do
        ifname=$(echo "$iface" | cut -d/ -f5)
        [ "$ifname" = "lo" ] && continue
        mac=$(cat "$iface")
        log "  $ifname: $mac"
    done

    log "CPU: $(grep -c ^processor /proc/cpuinfo) cores, $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"

    log "Memory: $(awk '/MemTotal/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo)"

    log "Disks:"
    lsblk -dno NAME,SIZE,TYPE 2>/dev/null | while read -r line; do
        log "  $line"
    done

    log "=== End Hardware Telemetry ==="
}

phone_home() {
    local jumpbox_url="${JUMPBOX_URL:-}"
    local node_name="${NODE_NAME:-$(hostname)}"

    if [ -z "$jumpbox_url" ]; then
        log "JUMPBOX_URL not set -- skipping phone-home"
        return 0
    fi

    log "Phoning home to $jumpbox_url"

    local payload
    payload=$(cat <<EOJSON
{
    "hostname": "$node_name",
    "event": "post-install-complete",
    "timestamp": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
    "mac": "$(cat /sys/class/net/$(ip route show default | awk '/default/ {print $5}' | head -1)/address 2>/dev/null || echo 'unknown')"
}
EOJSON
)

    curl -sf -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$jumpbox_url/api/v1/discovery" \
        --connect-timeout 10 \
        --max-time 30 \
    || log "WARNING: Phone-home failed (jumpbox may not have API listener yet)"
}

main() {
    log "OKD-Metal Discovery Agent starting"
    log "Post-install phase -- disk installation completed by coreos-installer"

    collect_hardware_info
    phone_home

    log "Discovery agent complete. System will reboot into installed OS."
}

main "$@"
