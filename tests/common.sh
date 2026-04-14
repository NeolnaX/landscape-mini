#!/bin/bash

if [[ -n "${LANDSCAPE_TEST_COMMON_SOURCED:-}" ]]; then
    return 0
fi
LANDSCAPE_TEST_COMMON_SOURCED=1

# ── Colors / Logging ──────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' NC=''
fi

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }

# ── Result Helpers ────────────────────────────────────────────────────────────

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FAIL_FAST="${FAIL_FAST:-0}"
LANDSCAPE_TEST_HTTP_TIMEOUT="${LANDSCAPE_TEST_HTTP_TIMEOUT:-10}"
LANDSCAPE_API_READY_TIMEOUT="${LANDSCAPE_API_READY_TIMEOUT:-45}"
LANDSCAPE_API_READY_INTERVAL="${LANDSCAPE_API_READY_INTERVAL:-3}"

run_check() {
    local desc="$1"
    shift
    local output rc

    if output=$("$@" 2>&1); then
        rc=0
    else
        rc=$?
    fi

    if [[ $rc -eq 0 ]]; then
        echo "[PASS] ${desc}"
        ((PASS_COUNT++))
    else
        echo "[FAIL] ${desc}"
        echo "       output: ${output}"
        ((FAIL_COUNT++))
        if [[ "${FAIL_FAST}" == "1" ]]; then
            exit $rc
        fi
    fi

    return $rc
}

run_skip() {
    local desc="$1"
    local reason="$2"
    echo "[SKIP] ${desc} — ${reason}"
    ((SKIP_COUNT++))
}

contains_text() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" == *"$needle"* ]]
}

contains_all_text() {
    local haystack="$1"
    shift
    local needle
    for needle in "$@"; do
        [[ "$haystack" == *"$needle"* ]] || return 1
    done
}

matches_regex() {
    local haystack="$1"
    local regex="$2"
    printf '%s\n' "$haystack" | grep -qE "$regex"
}

matches_regex_i() {
    local haystack="$1"
    local regex="$2"
    printf '%s\n' "$haystack" | grep -qiE "$regex"
}

# ── Generic Test Helpers ──────────────────────────────────────────────────────

require_commands() {
    local missing=()
    local cmd
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        return 1
    fi
}

ensure_local_ports_free() {
    local port
    for port in "$@"; do
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            error "Port ${port} is already in use. Is another QEMU instance running?"
            return 1
        fi
    done
}

detect_kvm() {
    if [[ -w /dev/kvm ]]; then
        info "KVM acceleration: enabled" >&2
        echo "-enable-kvm"
    else
        warn "KVM not available, using software emulation (slow)" >&2
        echo "-cpu qemu64"
    fi
}

detect_ovmf_firmware() {
    local path
    for path in /usr/share/ovmf/OVMF.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/ovmf/OVMF_CODE.fd; do
        if [[ -f "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    return 1
}

wait_for_pidfile() {
    local pidfile="$1"
    local label="$2"
    local timeout="${3:-10}"
    local elapsed=0
    local pid=""

    while [[ $elapsed -lt $timeout ]]; do
        if [[ -s "${pidfile}" ]]; then
            pid=$(cat "${pidfile}" 2>/dev/null || true)
            if [[ "$pid" =~ ^[0-9]+$ ]]; then
                echo "$pid"
                return 0
            fi
        fi
        sleep 1
        ((elapsed++))
    done

    error "${label} failed to write pidfile after ${timeout}s"
    return 1
}

dump_log_tail() {
    local logfile="$1"
    local label="${2:-$1}"
    if [[ -f "${logfile}" ]]; then
        echo ""
        error "=== Last 50 lines of ${label} ==="
        tail -n 50 "${logfile}" 2>/dev/null || true
        echo ""
    fi
}

# ── SSH Helpers ───────────────────────────────────────────────────────────────

SSH_ARGS=()
LANDSCAPE_TEST_REMOTE_TIMEOUT="${LANDSCAPE_TEST_REMOTE_TIMEOUT:-15}"

setup_ssh() {
    local user="${SSH_USER:-root}"
    local host="${SSH_HOST:-localhost}"
    SSH_ARGS=(
        timeout --foreground "${LANDSCAPE_TEST_REMOTE_TIMEOUT}"
        sshpass -p "${SSH_PASSWORD}" ssh
        -n
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o ConnectTimeout=10
        -o LogLevel=ERROR
        -p "${SSH_PORT}"
        "${user}@${host}"
    )
}

guest_run() {
    if [[ ${#SSH_ARGS[@]} -eq 0 ]]; then
        error "SSH helper not initialized; call setup_ssh first" >&2
        return 1
    fi
    "${SSH_ARGS[@]}" "$@"
}

wait_for_guest_ssh() {
    local pid="$1"
    local serial_log="$2"
    local label="$3"
    local timeout="${4:-${SSH_TIMEOUT:-60}}"

    info "Waiting for ${label} SSH (timeout: ${timeout}s)..."

    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if ! kill -0 "${pid}" 2>/dev/null; then
            error "${label} VM died unexpectedly"
            dump_log_tail "${serial_log}" "${label} serial log"
            return 1
        fi

        if guest_run "echo ready" &>/dev/null; then
            ok "SSH available after ${elapsed}s"
            return 0
        fi

        sleep 3
        ((elapsed += 3))
        if ((elapsed % 15 == 0)); then
            info "  ...still waiting (${elapsed}s)"
        fi
    done

    error "SSH timeout after ${timeout}s"
    dump_log_tail "${serial_log}" "${label} serial log"
    return 1
}

# ── Landscape API Compatibility Layer ─────────────────────────────────────────

API_BASE="${API_BASE:-}"
API_LAYOUT="${API_LAYOUT:-}"
API_AUTH_PATH="${API_AUTH_PATH:-/api/auth/login}"
API_USERNAME="${API_USERNAME:-root}"
API_PASSWORD="${API_PASSWORD:-root}"
LANDSCAPE_CONTROL_PORT="${LANDSCAPE_CONTROL_PORT:-6443}"

_landscape_api_preferred_prefixes() {
    case "${API_LAYOUT:-}" in
        v1)
            printf '%s\n' 'v1' 'src'
            ;;
        src)
            printf '%s\n' 'src' 'v1'
            ;;
        *)
            printf '%s\n' 'src' 'v1'
            ;;
    esac
}

_landscape_api_candidate_paths() {
    local key="$1"
    local arg="${2:-}"
    local prefix

    while IFS= read -r prefix; do
        case "$key" in
            interfaces)
                if [[ "$prefix" == 'v1' ]]; then
                    printf '/api/v1/interfaces/all\n'
                else
                    printf '/api/src/iface/new\n'
                fi
                ;;
            ipconfigs_status)
                if [[ "$prefix" == 'v1' ]]; then
                    printf '/api/v1/services/ip/status\n'
                else
                    printf '/api/src/services/ipconfigs/status\n'
                fi
                ;;
            nat_status)
                if [[ "$prefix" == 'v1' ]]; then
                    printf '/api/v1/services/nat/status\n'
                else
                    printf '/api/src/services/nats/status\n'
                fi
                ;;
            dhcp_status)
                printf '/api/%s/services/dhcp_v4/status\n' "$prefix"
                ;;
            route_wans_status)
                if [[ "$prefix" == 'v1' ]]; then
                    printf '/api/v1/services/wan/status\n'
                else
                    printf '/api/src/services/route_wans/status\n'
                fi
                ;;
            route_lans_status)
                if [[ "$prefix" == 'v1' ]]; then
                    printf '/api/v1/services/lan/status\n'
                else
                    printf '/api/src/services/route_lans/status\n'
                fi
                ;;
            dhcp_config)
                printf '/api/%s/services/dhcp_v4/%s\n' "$prefix" "$arg"
                ;;
            assigned_ips)
                printf '/api/%s/services/dhcp_v4/assigned_ips\n' "$prefix"
                ;;
            static_nat_mappings)
                if [[ "$prefix" == 'v1' ]]; then
                    printf '/api/v1/nat/static_mappings\n'
                else
                    printf '/api/src/config/static_nat_mappings\n'
                fi
                ;;
            dns_upstreams)
                if [[ "$prefix" == 'v1' ]]; then
                    printf '/api/v1/dns/upstreams\n'
                else
                    printf '/api/src/config/dns_upstreams\n'
                fi
                ;;
            config_export)
                if [[ "$prefix" == 'v1' ]]; then
                    printf '/api/v1/system/config/export\n'
                else
                    printf '/api/src/sys_service/config/export\n'
                fi
                ;;
            *)
                return 1
                ;;
        esac
    done < <(_landscape_api_preferred_prefixes)
}

landscape_api_get_path() {
    local token="$1"
    local path="$2"
    local auth_header auth_header_q url_q

    auth_header="Authorization: Bearer ${token}"
    printf -v auth_header_q '%q' "$auth_header"
    printf -v url_q '%q' "${API_BASE}${path}"

    guest_run "curl -sfkL --max-time ${LANDSCAPE_TEST_HTTP_TIMEOUT} -H ${auth_header_q} ${url_q}"
}

_landscape_api_get_operation() {
    local token="$1"
    local key="$2"
    local arg="${3:-}"
    local path response

    while IFS= read -r path; do
        response=$(landscape_api_get_path "$token" "$path" 2>/dev/null) && {
            echo "$response"
            return 0
        }
    done < <(_landscape_api_candidate_paths "$key" "$arg")

    return 1
}

detect_landscape_api_base() {
    API_BASE="https://localhost:${LANDSCAPE_CONTROL_PORT}"

    local elapsed=0
    local timeout="${1:-${LANDSCAPE_API_READY_TIMEOUT}}"
    local interval="${2:-${LANDSCAPE_API_READY_INTERVAL}}"

    while [[ $elapsed -lt $timeout ]]; do
        if guest_run "curl -skI --max-time ${LANDSCAPE_TEST_HTTP_TIMEOUT} ${API_BASE}/ -o /dev/null" &>/dev/null; then
            info "API base: ${API_BASE}"
            return 0
        fi

        sleep "${interval}"
        ((elapsed += interval))
        if ((elapsed < timeout)) && ((elapsed % 15 == 0)); then
            info "  ...waiting for Landscape API (${elapsed}s)"
        fi
    done

    error "Landscape API not reachable at ${API_BASE} after ${timeout}s"
    return 1
}

landscape_api_login() {
    local payload payload_q content_type_q url_q login_resp token
    local elapsed=0
    local timeout="${1:-${LANDSCAPE_API_READY_TIMEOUT}}"
    local interval="${2:-${LANDSCAPE_API_READY_INTERVAL}}"

    payload=$(jq -cn --arg username "$API_USERNAME" --arg password "$API_PASSWORD" '{username:$username,password:$password}')
    printf -v payload_q '%q' "$payload"
    printf -v content_type_q '%q' 'Content-Type: application/json'
    printf -v url_q '%q' "${API_BASE}${API_AUTH_PATH}"

    while [[ $elapsed -lt $timeout ]]; do
        login_resp=$(guest_run "curl -sfkL --max-time ${LANDSCAPE_TEST_HTTP_TIMEOUT} -H ${content_type_q} -X POST -d ${payload_q} ${url_q}" 2>/dev/null) || login_resp=""
        token=$(echo "$login_resp" | jq -r '.data.token // empty' 2>/dev/null || true)

        if [[ -n "$token" ]]; then
            echo "$token"
            return 0
        fi

        sleep "${interval}"
        ((elapsed += interval))
        if ((elapsed < timeout)) && ((elapsed % 15 == 0)); then
            info "  ...waiting for Landscape API auth (${elapsed}s)" >&2
        fi
    done

    return 1
}


detect_landscape_api_layout() {
    local token="$1"
    local elapsed=0
    local timeout="${2:-60}"

    while [[ $elapsed -lt $timeout ]]; do
        if landscape_api_get_path "$token" '/api/v1/services/dhcp_v4/status' &>/dev/null; then
            API_LAYOUT='v1'
            info "Detected API layout: ${API_LAYOUT}"
            return 0
        fi

        if landscape_api_get_path "$token" '/api/src/services/dhcp_v4/status' &>/dev/null; then
            API_LAYOUT='src'
            info "Detected API layout: ${API_LAYOUT}"
            return 0
        fi

        sleep 3
        ((elapsed += 3))
        if ((elapsed % 15 == 0)); then
            info "  ...waiting for supported API layout (${elapsed}s)"
        fi
    done

    error 'Unable to detect supported API layout'
    return 1
}

landscape_api_interfaces() {
    local token="$1"
    _landscape_api_get_operation "$token" 'interfaces'
}

landscape_api_service_status() {
    local token="$1"
    local service_key="$2"
    local op

    case "$service_key" in
        ipconfigs)
            op='ipconfigs_status'
            ;;
        nat)
            op='nat_status'
            ;;
        dhcp_v4)
            op='dhcp_status'
            ;;
        route_wans)
            op='route_wans_status'
            ;;
        route_lans)
            op='route_lans_status'
            ;;
        *)
            error "Unknown Landscape service key: ${service_key}" >&2
            return 1
            ;;
    esac

    _landscape_api_get_operation "$token" "$op"
}

landscape_api_service_active() {
    local token="$1"
    local service_key="$2"
    local iface="$3"

    landscape_api_service_status "$token" "$service_key" \
        | jq -r --arg key "$iface" '.data[$key].t // empty | select(. == "running") | "yes"'
}

landscape_api_dhcp_config() {
    local token="$1"
    local iface="$2"
    _landscape_api_get_operation "$token" 'dhcp_config' "$iface"
}

landscape_api_dhcp_assigned() {
    local token="$1"
    _landscape_api_get_operation "$token" 'assigned_ips'
}

landscape_api_dhcp_assigned_ip() {
    local token="$1"
    local subnet_prefix="$2"

    landscape_api_dhcp_assigned "$token" | jq -r --arg prefix "$subnet_prefix" '
        .data
        | to_entries[]?.value.offered_ips[]?.ip
        | select(type == "string" and startswith($prefix))
    ' | head -n 1
}

landscape_api_static_nat_mappings() {
    local token="$1"
    _landscape_api_get_operation "$token" 'static_nat_mappings'
}

landscape_api_dns_upstreams() {
    local token="$1"
    _landscape_api_get_operation "$token" 'dns_upstreams'
}

wait_for_landscape_service_active() {
    local token="$1"
    local service_key="$2"
    local iface="$3"
    local timeout="${4:-30}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if [[ "$(landscape_api_service_active "$token" "$service_key" "$iface" 2>/dev/null || true)" == "yes" ]]; then
            return 0
        fi
        sleep 2
        ((elapsed += 2))
    done

    return 1
}

landscape_api_config_export() {
    local token="$1"
    _landscape_api_get_operation "$token" 'config_export'
}
