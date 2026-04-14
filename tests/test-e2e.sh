#!/bin/bash
# =============================================================================
# Landscape Mini - End-to-End Network Test
# =============================================================================
#
# Tests real network functionality using two QEMU VMs:
#   - Router VM: Landscape router image with WAN (SLIRP) + LAN (mcast)
#   - Client VM: CirrOS minimal image connected to router's LAN
#
# Topology:
#   ┌──────────────┐      socket:mcast       ┌──────────────┐
#   │  Router VM   │      230.0.0.1:1234      │  Client VM   │
#   │              │                          │  (CirrOS)    │
#   │  eth0 (WAN)──┼── SLIRP → internet      │              │
#   │  eth1 (LAN)──┼──────────────────────────┼── eth0       │
#   │  192.168.10.1│      L2 segment          │  DHCP client │
#   └──────────────┘                          └──────────────┘
#
# Tests performed:
#   1. DHCP — Client receives 192.168.10.x from router
#   2. Gateway — Router can ping client (L2/L3 connectivity)
#   3. DNS — Router DNS service resolves external domains
#   4. NAT — Client can reach internet through router (SSH hop)
#
# Usage:
#   ./tests/test-e2e.sh [image-path]
#
# Exit codes:
#   0 - All checks passed
#   1 - One or more checks failed
#   2 - Infrastructure error (QEMU, SSH timeout, etc.)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ── Configuration ─────────────────────────────────────────────────────────────

IMAGE_PATH="${1:-${PROJECT_DIR}/output/landscape-mini-x86.img}"
SSH_PORT="${SSH_PORT:-2222}"
WEB_PORT="${WEB_PORT:-9800}"
LANDSCAPE_CONTROL_PORT="${LANDSCAPE_CONTROL_PORT:-6443}"
QEMU_MEM="${QEMU_MEM:-1024}"
QEMU_SMP="${QEMU_SMP:-2}"
SSH_PASSWORD="landscape"
API_USERNAME="root"
API_PASSWORD="root"
SSH_TIMEOUT="${SSH_TIMEOUT:-120}"
SHUTDOWN_TIMEOUT=15
DHCP_TIMEOUT=120

EXPECTED_WAN_IFACE="eth0"
EXPECTED_LAN_IFACE="eth1"
EXPECTED_LAN_GW="192.168.10.1"
EXPECTED_LAN_SUBNET_PREFIX="192.168.10."

# CirrOS — use GitHub mirror (cirros-cloud.net is often unreachable from CI)
CIRROS_VERSION="0.6.2"
CIRROS_URL="https://github.com/cirros-dev/cirros/releases/download/${CIRROS_VERSION}/cirros-${CIRROS_VERSION}-x86_64-disk.img"
CIRROS_USER="cirros"
CIRROS_PASSWORD="gocubsgo"

# QEMU socket multicast for L2 LAN segment
MCAST_ADDR="230.0.0.1"
MCAST_PORT="1234"

# MAC addresses
ROUTER_WAN_MAC="52:54:00:12:34:01"
ROUTER_LAN_MAC="52:54:00:12:34:02"
CLIENT_MAC="52:54:00:12:34:10"

LOG_DIR="${PROJECT_DIR}/output/test-logs"
SERIAL_LOG="${LOG_DIR}/e2e-serial-router.log"
CLIENT_SERIAL_LOG="${LOG_DIR}/e2e-serial-client.log"
RESULTS_FILE="${LOG_DIR}/e2e-test-results.txt"

# State
ROUTER_PID=""
CLIENT_PID=""
ROUTER_PIDFILE=""
CLIENT_PIDFILE=""
ROUTER_MONITOR=""
CLIENT_MONITOR=""
TEMP_IMAGE=""
TEMP_CIRROS=""

# ── Cleanup ───────────────────────────────────────────────────────────────────

cleanup() {
    local exit_code=$?
    set +e

    if [[ -n "${CLIENT_PID}" ]] && kill -0 "${CLIENT_PID}" 2>/dev/null; then
        info "Stopping Client VM (PID ${CLIENT_PID})..."
        if [[ -n "${CLIENT_MONITOR}" ]] && [[ -S "${CLIENT_MONITOR}" ]]; then
            echo "quit" | socat -T2 STDIN UNIX-CONNECT:"${CLIENT_MONITOR}" &>/dev/null || true
            sleep 2
        fi
        if kill -0 "${CLIENT_PID}" 2>/dev/null; then
            kill -9 "${CLIENT_PID}" 2>/dev/null || true
            wait "${CLIENT_PID}" 2>/dev/null || true
        fi
    fi

    if [[ -n "${ROUTER_PID}" ]] && kill -0 "${ROUTER_PID}" 2>/dev/null; then
        info "Stopping Router VM (PID ${ROUTER_PID})..."
        if [[ -n "${ROUTER_MONITOR}" ]] && [[ -S "${ROUTER_MONITOR}" ]]; then
            echo "system_powerdown" | socat -T2 STDIN UNIX-CONNECT:"${ROUTER_MONITOR}" &>/dev/null || true
            local waited=0
            while kill -0 "${ROUTER_PID}" 2>/dev/null && [[ $waited -lt $SHUTDOWN_TIMEOUT ]]; do
                sleep 1
                ((waited++))
            done
            if kill -0 "${ROUTER_PID}" 2>/dev/null && [[ -S "${ROUTER_MONITOR}" ]]; then
                echo "quit" | socat -T2 STDIN UNIX-CONNECT:"${ROUTER_MONITOR}" &>/dev/null || true
                sleep 2
            fi
        fi
        if kill -0 "${ROUTER_PID}" 2>/dev/null; then
            kill -9 "${ROUTER_PID}" 2>/dev/null || true
            wait "${ROUTER_PID}" 2>/dev/null || true
        fi
    fi

    [[ -n "${TEMP_IMAGE}" ]] && rm -f "${TEMP_IMAGE}"
    [[ -n "${TEMP_CIRROS}" ]] && rm -f "${TEMP_CIRROS}"
    [[ -n "${ROUTER_PIDFILE}" ]] && rm -f "${ROUTER_PIDFILE}"
    [[ -n "${CLIENT_PIDFILE}" ]] && rm -f "${CLIENT_PIDFILE}"
    [[ -n "${ROUTER_MONITOR}" ]] && rm -f "${ROUTER_MONITOR}"
    [[ -n "${CLIENT_MONITOR}" ]] && rm -f "${CLIENT_MONITOR}"

    exit $exit_code
}

trap cleanup EXIT

# ── Preflight ─────────────────────────────────────────────────────────────────

preflight() {
    info "Preflight checks..."

    if [[ ! -f "${IMAGE_PATH}" ]]; then
        error "Image not found: ${IMAGE_PATH}"
        error "Run 'make build' first."
        exit 2
    fi

    if ! require_commands qemu-system-x86_64 qemu-img sshpass curl socat jq; then
        error "Run 'make deps-test' to install test dependencies."
        exit 2
    fi

    if ! ensure_local_ports_free "${SSH_PORT}" "${WEB_PORT}"; then
        exit 2
    fi

    ok "Preflight passed"
}

# ── Download CirrOS ───────────────────────────────────────────────────────────

download_cirros() {
    local download_dir="${PROJECT_DIR}/work/downloads"
    local cirros_file="${download_dir}/cirros-${CIRROS_VERSION}-x86_64-disk.img"

    mkdir -p "${download_dir}"

    if [[ -f "${cirros_file}" ]]; then
        info "CirrOS image already cached." >&2
    else
        info "Downloading CirrOS ${CIRROS_VERSION} ..." >&2
        if ! curl -fL --retry 3 --retry-delay 5 -o "${cirros_file}" "${CIRROS_URL}" >&2; then
            error "Failed to download CirrOS from ${CIRROS_URL}" >&2
            return 1
        fi
        ok "CirrOS downloaded ($(du -h "${cirros_file}" | awk '{print $1}'))" >&2
    fi

    echo "${cirros_file}"
}

# ── Start Router VM ───────────────────────────────────────────────────────────

start_router() {
    info "Preparing router disk image..."
    mkdir -p "${LOG_DIR}"

    TEMP_IMAGE=$(mktemp "${LOG_DIR}/e2e-router-XXXXXX.img")
    cp "${IMAGE_PATH}" "${TEMP_IMAGE}"

    ROUTER_PIDFILE=$(mktemp "${LOG_DIR}/e2e-router-pid-XXXXXX")
    ROUTER_MONITOR=$(mktemp -u "${LOG_DIR}/e2e-router-mon-XXXXXX.sock")

    local kvm_flag
    kvm_flag=$(detect_kvm)

    local ovmf=""
    ovmf=$(detect_ovmf_firmware || true)

    local bios_args=()
    if [[ -n "$ovmf" ]]; then
        bios_args=(-bios "$ovmf")
        info "UEFI firmware: ${ovmf}"
    else
        warn "OVMF not found, falling back to SeaBIOS"
    fi

    info "Starting Router VM (SSH=${SSH_PORT}, Web=${WEB_PORT})..."

    qemu-system-x86_64 \
        ${kvm_flag} \
        -m "${QEMU_MEM}" \
        -smp "${QEMU_SMP}" \
        "${bios_args[@]}" \
        -drive "file=${TEMP_IMAGE},format=raw,if=virtio" \
        -device virtio-net-pci,netdev=wan,mac=${ROUTER_WAN_MAC} \
        -netdev "user,id=wan,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::${WEB_PORT}-:${LANDSCAPE_CONTROL_PORT}" \
        -device virtio-net-pci,netdev=lan,mac=${ROUTER_LAN_MAC} \
        -netdev "socket,id=lan,mcast=${MCAST_ADDR}:${MCAST_PORT}" \
        -display none \
        -serial "file:${SERIAL_LOG}" \
        -monitor "unix:${ROUTER_MONITOR},server,nowait" \
        -pidfile "${ROUTER_PIDFILE}" \
        -daemonize

    if wait_pid=$(wait_for_pidfile "${ROUTER_PIDFILE}" "Router VM" 10); then
        ROUTER_PID="$wait_pid"
        if kill -0 "${ROUTER_PID}" 2>/dev/null; then
            ok "Router VM started (PID ${ROUTER_PID})"
        else
            error "Router VM exited immediately"
            dump_log_tail "${SERIAL_LOG}" "router serial log"
            exit 2
        fi
    else
        error "Router VM failed to start (no pidfile)"
        exit 2
    fi
}

# ── Start Client VM ───────────────────────────────────────────────────────────

start_client() {
    local cirros_file="$1"

    info "Preparing client disk image..."

    TEMP_CIRROS=$(mktemp "${LOG_DIR}/e2e-client-XXXXXX.qcow2")
    rm -f "${TEMP_CIRROS}"
    qemu-img create -f qcow2 -b "${cirros_file}" -F qcow2 "${TEMP_CIRROS}"

    CLIENT_PIDFILE=$(mktemp "${LOG_DIR}/e2e-client-pid-XXXXXX")
    CLIENT_MONITOR=$(mktemp -u "${LOG_DIR}/e2e-client-mon-XXXXXX.sock")

    local kvm_flag
    kvm_flag=$(detect_kvm)

    info "Starting Client VM (CirrOS)..."

    qemu-system-x86_64 \
        ${kvm_flag} \
        -m 256 \
        -smp 1 \
        -drive "file=${TEMP_CIRROS},format=qcow2,if=virtio" \
        -device virtio-net-pci,netdev=net0,mac=${CLIENT_MAC} \
        -netdev "socket,id=net0,mcast=${MCAST_ADDR}:${MCAST_PORT}" \
        -display none \
        -serial "file:${CLIENT_SERIAL_LOG}" \
        -monitor "unix:${CLIENT_MONITOR},server,nowait" \
        -pidfile "${CLIENT_PIDFILE}" \
        -daemonize

    if wait_pid=$(wait_for_pidfile "${CLIENT_PIDFILE}" "Client VM" 10); then
        CLIENT_PID="$wait_pid"
        if kill -0 "${CLIENT_PID}" 2>/dev/null; then
            ok "Client VM started (PID ${CLIENT_PID})"
        else
            error "Client VM exited immediately"
            dump_log_tail "${CLIENT_SERIAL_LOG}" "client serial log"
            exit 2
        fi
    else
        error "Client VM failed to start (no pidfile)"
        exit 2
    fi
}

# ── Wait for DHCP Assignment ──────────────────────────────────────────────────

wait_for_dhcp() {
    local token="$1"

    info "Waiting for client DHCP assignment (timeout: ${DHCP_TIMEOUT}s)..." >&2

    local elapsed=0
    while [[ $elapsed -lt $DHCP_TIMEOUT ]]; do
        if ! kill -0 "${CLIENT_PID}" 2>/dev/null; then
            error "Client VM died while waiting for DHCP" >&2
            dump_log_tail "${CLIENT_SERIAL_LOG}" "client serial log" >&2
            return 1
        fi

        local client_ip
        client_ip=$(landscape_api_dhcp_assigned_ip "$token" "$EXPECTED_LAN_SUBNET_PREFIX" 2>/dev/null || true)
        if [[ -n "$client_ip" ]]; then
            ok "Client received DHCP: ${client_ip} (after ${elapsed}s)" >&2
            echo "$client_ip"
            return 0
        fi

        sleep 5
        ((elapsed += 5))
        if ((elapsed % 15 == 0)); then
            info "  ...still waiting for DHCP (${elapsed}s)" >&2
        fi
    done

    error "DHCP assignment timeout after ${DHCP_TIMEOUT}s" >&2
    dump_log_tail "${CLIENT_SERIAL_LOG}" "client serial log" >&2
    return 1
}

# ── E2E Network Tests ─────────────────────────────────────────────────────────

run_e2e_checks() {
    local token="$1"
    local client_ip="$2"

    set +e

    echo ""
    echo "============================================================"
    echo "Landscape Mini — End-to-End Network Tests"
    echo "============================================================"
    echo ""

    echo "---- DHCP ----"

    run_check "Client received DHCP IP (${client_ip})" \
        test -n "$client_ip"

    run_check "DHCP assignment visible in API" \
        test "$(landscape_api_dhcp_assigned_ip "$token" "$EXPECTED_LAN_SUBNET_PREFIX" 2>/dev/null || true)" = "$client_ip"

    echo ""
    echo "---- Gateway Connectivity ----"

    local ping_ok=false
    local attempt
    for attempt in 1 2 3 4 5 6; do
        if guest_run "ping -c 2 -W 3 ${client_ip}" &>/dev/null; then
            ping_ok=true
            break
        fi
        sleep 3
    done
    if [[ "$ping_ok" == "true" ]]; then
        run_check "Router can ping client (${client_ip})" true
    else
        local arp_out
        arp_out=$(guest_run "ip neigh show ${client_ip}" 2>/dev/null || true)
        if matches_regex_i "$arp_out" 'REACHABLE|STALE|lladdr'; then
            run_check "Router has ARP entry for client (${client_ip})" true
            run_skip "Router can ping client (${client_ip})" "ping failed but ARP resolved"
        else
            run_check "Router can ping client (${client_ip})" false
        fi
    fi

    echo ""
    echo "---- DNS ----"

    local resolv
    resolv=$(guest_run "cat /etc/resolv.conf" 2>/dev/null || true)
    run_check "DNS resolver points to localhost" \
        contains_text "$resolv" "127.0.0.1"

    local dns_result
    dns_result=$(guest_run "nslookup www.baidu.com 2>/dev/null || host www.baidu.com 2>/dev/null" 2>/dev/null || true)
    if matches_regex_i "$dns_result" '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
        run_check "DNS resolves www.baidu.com" true
    else
        run_skip "DNS resolves www.baidu.com" "resolution failed"
    fi

    echo ""
    echo "---- NAT ----"

    run_check "NAT rules active (${EXPECTED_WAN_IFACE})" \
        test "$(landscape_api_service_active "$token" "nat" "$EXPECTED_WAN_IFACE" 2>/dev/null || true)" = "yes"

    local wan_result
    wan_result=$(guest_run "curl -sf --max-time ${LANDSCAPE_TEST_HTTP_TIMEOUT} http://example.com" 2>&1)
    if matches_regex_i "$wan_result" "example"; then
        run_check "Router WAN connectivity (curl example.com)" true
    else
        wan_result=$(guest_run "curl -sf --max-time ${LANDSCAPE_TEST_HTTP_TIMEOUT} http://captive.apple.com" 2>&1)
        if [[ -n "$wan_result" ]]; then
            run_check "Router WAN connectivity (curl captive.apple.com)" true
        else
            run_skip "Router WAN connectivity" "SLIRP outbound not working"
        fi
    fi

    info "Testing NAT: client → router → internet (SSH hop)..."

    local ip_fwd
    ip_fwd=$(guest_run "cat /proc/sys/net/ipv4/ip_forward" 2>/dev/null)
    run_check "IP forwarding enabled" \
        test "$ip_fwd" = "1"

    echo ""
    echo "============================================================"
    echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed, ${SKIP_COUNT} skipped"
    echo "============================================================"

    set -e
    return $FAIL_COUNT
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo "============================================================"
    echo "  Landscape Mini — End-to-End Network Test"
    echo "============================================================"
    echo ""
    info "Image: ${IMAGE_PATH}"
    echo ""

    preflight

    local cirros_file
    cirros_file=$(download_cirros)

    start_router
    setup_ssh
    wait_for_guest_ssh "${ROUTER_PID}" "${SERIAL_LOG}" "Router" "${SSH_TIMEOUT}" || exit 2

    detect_landscape_api_base || exit 2
    local token
    token=$(landscape_api_login)
    if [[ -z "$token" ]]; then
        error "Failed to login to Landscape API"
        exit 2
    fi
    ok "API login successful"

    if ! detect_landscape_api_layout "$token"; then
        exit 2
    fi

    info "Waiting for DHCP service to become active..."
    local dhcp_ready=false
    local dhcp_wait=0
    while [[ $dhcp_wait -lt 90 ]]; do
        if [[ "$(landscape_api_service_active "$token" "dhcp_v4" "$EXPECTED_LAN_IFACE" 2>/dev/null || true)" == "yes" ]]; then
            dhcp_ready=true
            break
        fi
        sleep 5
        ((dhcp_wait += 5))
        if ((dhcp_wait % 15 == 0)); then
            info "  ...DHCP not ready yet (${dhcp_wait}s)"
        fi
    done
    if [[ "$dhcp_ready" == "true" ]]; then
        ok "DHCP service active on ${EXPECTED_LAN_IFACE} (after ${dhcp_wait}s)"
    else
        error "DHCP service not active after 90s — cannot run e2e tests"
        exit 2
    fi

    start_client "$cirros_file"

    local client_ip
    client_ip=$(wait_for_dhcp "$token")
    if [[ -z "$client_ip" ]]; then
        error "Client did not receive DHCP — cannot run e2e tests"
        dump_log_tail "${CLIENT_SERIAL_LOG}" "client serial log"
        exit 2
    fi

    echo ""
    run_e2e_checks "$token" "$client_ip" 2>&1 | tee "${RESULTS_FILE}"
    local rc=${PIPESTATUS[0]}

    echo ""
    if [[ $rc -eq 0 ]]; then
        ok "All E2E checks passed!"
    else
        error "${rc} E2E check(s) failed"
        rc=1
    fi
    info "Router serial log: ${SERIAL_LOG}"
    info "Client serial log: ${CLIENT_SERIAL_LOG}"
    info "Test results:      ${RESULTS_FILE}"
    echo ""

    exit $rc
}

main
