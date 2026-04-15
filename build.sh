#!/bin/bash
set -euo pipefail

# =============================================================================
# Landscape Mini - Minimal x86 UEFI Image Builder
# =============================================================================
# Orchestrator: sources lib/common.sh + backend (lib/debian.sh or lib/alpine.sh)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration
if [[ -f "${SCRIPT_DIR}/build.env" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/build.env"
else
    echo "ERROR: build.env not found in ${SCRIPT_DIR}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Parse command line arguments
# ---------------------------------------------------------------------------
SKIP_TO_PHASE=0
EFFECTIVE_CONFIG_PATH="${EFFECTIVE_CONFIG_PATH:-}"
EFFECTIVE_CONFIG_PROFILE="${EFFECTIVE_CONFIG_PROFILE:-default}"
EFFECTIVE_TOPOLOGY_SOURCE="${EFFECTIVE_TOPOLOGY_SOURCE:-default}"
ROOT_PASSWORD_SOURCE="${ROOT_PASSWORD_SOURCE:-default}"
LANDSCAPE_ADMIN_USER="${LANDSCAPE_ADMIN_USER:-root}"
LANDSCAPE_ADMIN_USER_SOURCE="${LANDSCAPE_ADMIN_USER_SOURCE:-default}"
LANDSCAPE_ADMIN_PASS="${LANDSCAPE_ADMIN_PASS:-root}"
LANDSCAPE_ADMIN_PASS_SOURCE="${LANDSCAPE_ADMIN_PASS_SOURCE:-default}"

declare -a CLI_OUTPUT_FORMATS=()
declare -a OUTPUT_FORMAT_LIST=()

action_usage() {
    cat <<'EOF'
Usage:
  ./build.sh [options]

Options:
  --base-system debian|alpine
  --include-docker true|false
  --output-format img|vmdk|pve-ova   (repeatable)
  --version VERSION
  --skip-to PHASE
EOF
}

join_by() {
    local delimiter="$1"
    shift || true
    local first=1
    local value
    for value in "$@"; do
        if [[ ${first} -eq 1 ]]; then
            printf '%s' "${value}"
            first=0
        else
            printf '%s%s' "${delimiter}" "${value}"
        fi
    done
}

validate_base_system() {
    case "$1" in
        debian|alpine)
            ;;
        *)
            echo "ERROR: BASE_SYSTEM must be 'debian' or 'alpine', got '$1'." >&2
            exit 1
            ;;
    esac
}

validate_include_docker() {
    case "$1" in
        true|false)
            ;;
        *)
            echo "ERROR: INCLUDE_DOCKER must be 'true' or 'false', got '$1'." >&2
            exit 1
            ;;
    esac
}

validate_output_format() {
    case "$1" in
        img|vmdk|pve-ova)
            ;;
        *)
            echo "ERROR: Unsupported output format '$1'. Use img, vmdk, or pve-ova." >&2
            exit 1
            ;;
    esac
}

normalize_output_formats() {
    local -a raw_items=()
    local -a normalized=()
    local raw_value trimmed value
    local seen=","

    if [[ ${#CLI_OUTPUT_FORMATS[@]} -gt 0 ]]; then
        raw_items=("${CLI_OUTPUT_FORMATS[@]}")
    else
        IFS=',' read -r -a raw_items <<< "${OUTPUT_FORMATS}"
    fi

    for raw_value in "${raw_items[@]}"; do
        trimmed="${raw_value//[[:space:]]/}"
        [[ -n "${trimmed}" ]] || continue
        validate_output_format "${trimmed}"
        if [[ "${seen}" == *",${trimmed},"* ]]; then
            continue
        fi
        normalized+=("${trimmed}")
        seen+="${trimmed},"
    done

    if [[ ${#normalized[@]} -eq 0 ]]; then
        echo "ERROR: At least one output format is required." >&2
        exit 1
    fi

    OUTPUT_FORMAT_LIST=("${normalized[@]}")
    OUTPUT_FORMATS="$(join_by , "${OUTPUT_FORMAT_LIST[@]}")"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-system)
            if [[ -n "${2:-}" ]]; then
                BASE_SYSTEM="$2"
                shift 2
            else
                echo "ERROR: --base-system requires 'debian' or 'alpine'" >&2
                exit 1
            fi
            ;;
        --include-docker)
            if [[ -n "${2:-}" ]]; then
                INCLUDE_DOCKER="$2"
                shift 2
            else
                echo "ERROR: --include-docker requires 'true' or 'false'" >&2
                exit 1
            fi
            ;;
        --output-format)
            if [[ -n "${2:-}" ]]; then
                CLI_OUTPUT_FORMATS+=("$2")
                shift 2
            else
                echo "ERROR: --output-format requires img, vmdk, or pve-ova" >&2
                exit 1
            fi
            ;;
        --version)
            if [[ -n "${2:-}" ]]; then
                LANDSCAPE_VERSION="$2"
                shift 2
            else
                echo "ERROR: --version requires a value (e.g. --version v0.12.4)" >&2
                exit 1
            fi
            ;;
        --skip-to)
            if [[ -n "${2:-}" && "${2:-}" =~ ^[1-8]$ ]]; then
                SKIP_TO_PHASE="$2"
                shift 2
            else
                echo "ERROR: --skip-to requires a phase number (1-8)" >&2
                exit 1
            fi
            ;;
        --help|-h)
            action_usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            action_usage >&2
            exit 1
            ;;
    esac
done

validate_base_system "${BASE_SYSTEM}"
validate_include_docker "${INCLUDE_DOCKER}"
normalize_output_formats

# ---------------------------------------------------------------------------
# Must run as root
# ---------------------------------------------------------------------------
if [[ ${EUID} -ne 0 ]]; then
    echo "ERROR: This script must be run as root (use sudo)."
    exit 1
fi

# ---------------------------------------------------------------------------
# Source shared library and backend
# ---------------------------------------------------------------------------
source "${SCRIPT_DIR}/lib/common.sh"

case "${BASE_SYSTEM}" in
    debian)
        source "${SCRIPT_DIR}/lib/debian.sh"
        ;;
    alpine)
        source "${SCRIPT_DIR}/lib/alpine.sh"
        ;;
    *)
        echo "ERROR: Unknown base system '${BASE_SYSTEM}'. Use 'debian' or 'alpine'."
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
WORK_DIR="$(pwd)/work"
OUTPUT_DIR="$(pwd)/output"
OUTPUT_METADATA_DIR="${OUTPUT_DIR}/metadata"
ROOTFS_DIR="${WORK_DIR}/rootfs"
DOWNLOAD_DIR="${WORK_DIR}/downloads/${LANDSCAPE_VERSION}"
LOOP_DEV=""
SOURCE_PROBE_TIMEOUT="${SOURCE_PROBE_TIMEOUT:-5}"

BUILD_NAME="landscape-mini-x86-${BASE_SYSTEM}"
if [[ "${INCLUDE_DOCKER}" == "true" ]]; then
    BUILD_NAME+="-docker"
fi

IMAGE_FILE="${OUTPUT_DIR}/${BUILD_NAME}.img"
VMDK_FILE="${OUTPUT_DIR}/${BUILD_NAME}.vmdk"
PVE_OVA_FILE="${OUTPUT_DIR}/${BUILD_NAME}.ova"
BUILD_METADATA_FILE="${OUTPUT_METADATA_DIR}/build-metadata.txt"
RESOLVED_SOURCES_FILE="${OUTPUT_METADATA_DIR}/resolved-sources.env"

output_format_requested() {
    local requested="$1"
    local format
    for format in "${OUTPUT_FORMAT_LIST[@]}"; do
        if [[ "${format}" == "${requested}" ]]; then
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Source resolution helpers
# ---------------------------------------------------------------------------
resolve_build_sources() {
    echo ""
    echo "==== Source Resolution ===="

    if [[ "${BASE_SYSTEM}" == "debian" ]]; then
        resolve_source \
            "Debian APT mirror" \
            "${APT_MIRROR}" \
            "${APT_MIRROR_CANDIDATES}" \
            "debian-package" \
            "/dists/${DEBIAN_RELEASE}/main/binary-amd64/Packages.xz" \
            "RESOLVED_APT_MIRROR" \
            "RESOLVED_APT_MIRROR_SOURCE" \
            "${SOURCE_PROBE_TIMEOUT}"
        RESOLVED_ALPINE_MIRROR=""
        RESOLVED_ALPINE_MIRROR_SOURCE="unused"
    else
        resolve_source \
            "Alpine mirror" \
            "${ALPINE_MIRROR}" \
            "${ALPINE_MIRROR_CANDIDATES}" \
            "alpine-package" \
            "/${ALPINE_RELEASE}/main/x86_64" \
            "RESOLVED_ALPINE_MIRROR" \
            "RESOLVED_ALPINE_MIRROR_SOURCE" \
            "${SOURCE_PROBE_TIMEOUT}"
        RESOLVED_APT_MIRROR=""
        RESOLVED_APT_MIRROR_SOURCE="unused"
    fi

    if [[ "${INCLUDE_DOCKER}" == "true" && "${BASE_SYSTEM}" == "debian" ]]; then
        resolve_source \
            "Docker APT mirror" \
            "${DOCKER_APT_MIRROR}" \
            "${DOCKER_APT_MIRROR_CANDIDATES}" \
            "plain-debian-package" \
            "/dists/${DEBIAN_RELEASE}/stable/binary-amd64/Packages" \
            "RESOLVED_DOCKER_APT_MIRROR" \
            "RESOLVED_DOCKER_APT_MIRROR_SOURCE" \
            "${SOURCE_PROBE_TIMEOUT}"

        resolve_source \
            "Docker APT GPG URL" \
            "${DOCKER_APT_GPG_URL}" \
            "${DOCKER_APT_GPG_URL_CANDIDATES}" \
            "direct" \
            "" \
            "RESOLVED_DOCKER_APT_GPG_URL" \
            "RESOLVED_DOCKER_APT_GPG_URL_SOURCE" \
            "${SOURCE_PROBE_TIMEOUT}"
    else
        RESOLVED_DOCKER_APT_MIRROR=""
        RESOLVED_DOCKER_APT_MIRROR_SOURCE="unused"
        RESOLVED_DOCKER_APT_GPG_URL=""
        RESOLVED_DOCKER_APT_GPG_URL_SOURCE="unused"
    fi

    if [[ "${BASE_SYSTEM}" == "alpine" ]]; then
        MIRROR="${RESOLVED_ALPINE_MIRROR}"
    else
        MIRROR="${RESOLVED_APT_MIRROR}"
    fi

    DOCKER_MIRROR_DISPLAY="${RESOLVED_DOCKER_APT_MIRROR:-}"
    DOCKER_GPG_DISPLAY="${RESOLVED_DOCKER_APT_GPG_URL:-}"

    mkdir -p "${OUTPUT_METADATA_DIR}"
    printf '%s\n' \
        "resolved_apt_mirror=${RESOLVED_APT_MIRROR}" \
        "resolved_apt_mirror_source=${RESOLVED_APT_MIRROR_SOURCE}" \
        "resolved_alpine_mirror=${RESOLVED_ALPINE_MIRROR}" \
        "resolved_alpine_mirror_source=${RESOLVED_ALPINE_MIRROR_SOURCE}" \
        "resolved_docker_apt_mirror=${RESOLVED_DOCKER_APT_MIRROR}" \
        "resolved_docker_apt_mirror_source=${RESOLVED_DOCKER_APT_MIRROR_SOURCE}" \
        "resolved_docker_apt_gpg_url=${RESOLVED_DOCKER_APT_GPG_URL}" \
        "resolved_docker_apt_gpg_url_source=${RESOLVED_DOCKER_APT_GPG_URL_SOURCE}" \
        > "${RESOLVED_SOURCES_FILE}"

    echo "  Source resolution complete."
}

load_resolved_sources() {
    if [[ ! -f "${RESOLVED_SOURCES_FILE}" ]]; then
        echo "ERROR: Missing ${RESOLVED_SOURCES_FILE} for resumed build." >&2
        return 1
    fi

    # shellcheck disable=SC1090
    source "${RESOLVED_SOURCES_FILE}"

    RESOLVED_APT_MIRROR="${resolved_apt_mirror:-}"
    RESOLVED_APT_MIRROR_SOURCE="${resolved_apt_mirror_source:-unknown}"
    RESOLVED_ALPINE_MIRROR="${resolved_alpine_mirror:-}"
    RESOLVED_ALPINE_MIRROR_SOURCE="${resolved_alpine_mirror_source:-unknown}"
    RESOLVED_DOCKER_APT_MIRROR="${resolved_docker_apt_mirror:-}"
    RESOLVED_DOCKER_APT_MIRROR_SOURCE="${resolved_docker_apt_mirror_source:-unknown}"
    RESOLVED_DOCKER_APT_GPG_URL="${resolved_docker_apt_gpg_url:-}"
    RESOLVED_DOCKER_APT_GPG_URL_SOURCE="${resolved_docker_apt_gpg_url_source:-unknown}"

    if [[ "${BASE_SYSTEM}" == "alpine" ]]; then
        MIRROR="${RESOLVED_ALPINE_MIRROR}"
    else
        MIRROR="${RESOLVED_APT_MIRROR}"
    fi

    DOCKER_MIRROR_DISPLAY="${RESOLVED_DOCKER_APT_MIRROR:-}"
    DOCKER_GPG_DISPLAY="${RESOLVED_DOCKER_APT_GPG_URL:-}"

    echo "  Reusing resolved sources from ${RESOLVED_SOURCES_FILE}."
}

should_resolve_sources() {
    if [[ ${SKIP_TO_PHASE} -le 4 ]]; then
        return 0
    fi

    if [[ "${INCLUDE_DOCKER}" == "true" && ${SKIP_TO_PHASE} -le 6 ]]; then
        return 0
    fi

    return 1
}

# Determine download base URL
if [[ "${LANDSCAPE_VERSION}" == "latest" ]]; then
    DOWNLOAD_BASE="${LANDSCAPE_REPO}/releases/latest/download"
else
    DOWNLOAD_BASE="${LANDSCAPE_REPO}/releases/download/${LANDSCAPE_VERSION}"
fi

# ---------------------------------------------------------------------------
# Setup trap
# ---------------------------------------------------------------------------
trap cleanup EXIT ERR

main() {
    backend_check_deps

    if should_resolve_sources; then
        resolve_build_sources
    elif [[ ${SKIP_TO_PHASE} -gt 0 ]]; then
        load_resolved_sources
    fi

    echo "============================================================"
    echo "  Landscape Mini - x86 UEFI Image Builder"
    echo "============================================================"
    echo "  Build Name        : ${BUILD_NAME}"
    echo "  Base System       : ${BASE_SYSTEM}"
    echo "  Include Docker    : ${INCLUDE_DOCKER}"
    echo "  Output Formats    : ${OUTPUT_FORMATS}"
    echo "  Landscape Version : ${LANDSCAPE_VERSION}"
    echo "  Download Source   : ${DOWNLOAD_BASE}"
    if [[ "${BASE_SYSTEM}" == "debian" ]]; then
        echo "  Debian Release    : ${DEBIAN_RELEASE}"
        echo "  APT Mirror        : ${MIRROR} (${RESOLVED_APT_MIRROR_SOURCE})"
    else
        echo "  Alpine Release    : ${ALPINE_RELEASE}"
        echo "  Alpine Mirror     : ${MIRROR} (${RESOLVED_ALPINE_MIRROR_SOURCE})"
    fi
    echo "  Image Size        : ${IMAGE_SIZE_MB} MB"
    if [[ "${INCLUDE_DOCKER}" == "true" && "${BASE_SYSTEM}" == "debian" ]]; then
        echo "  Docker APT Mirror : ${DOCKER_MIRROR_DISPLAY} (${RESOLVED_DOCKER_APT_MIRROR_SOURCE})"
        echo "  Docker GPG URL    : ${DOCKER_GPG_DISPLAY} (${RESOLVED_DOCKER_APT_GPG_URL_SOURCE})"
    elif [[ "${INCLUDE_DOCKER}" == "true" && "${BASE_SYSTEM}" == "alpine" ]]; then
        echo "  Docker Source     : Alpine packages via ${MIRROR} (${RESOLVED_ALPINE_MIRROR_SOURCE})"
    fi
    echo "  Compress Output   : ${COMPRESS_OUTPUT}"
    echo "  Config Profile    : ${EFFECTIVE_CONFIG_PROFILE}"
    echo "  Topology Source   : ${EFFECTIVE_TOPOLOGY_SOURCE}"
    echo "  Admin User        : ${LANDSCAPE_ADMIN_USER}"
    echo "============================================================"

    if [[ ${SKIP_TO_PHASE} -gt 0 ]]; then
        echo ""
        echo "==== Resuming from Phase ${SKIP_TO_PHASE} ===="
        echo "  Phase 1: Download      | Phase 5: Install Landscape"
        echo "  Phase 2: Create Image  | Phase 6: Install Docker"
        echo "  Phase 3: Bootstrap     | Phase 7: Cleanup & Export"
        echo "  Phase 4: Configure     | Phase 8: Report"
    fi

    [[ ${SKIP_TO_PHASE} -le 1 ]] && phase_download

    if [[ ${SKIP_TO_PHASE} -le 2 ]]; then
        phase_create_image
    elif [[ ${SKIP_TO_PHASE} -le 7 ]]; then
        resume_from_image
    fi

    [[ ${SKIP_TO_PHASE} -le 3 ]] && backend_bootstrap
    [[ ${SKIP_TO_PHASE} -le 4 ]] && backend_configure
    [[ ${SKIP_TO_PHASE} -le 5 ]] && phase_install_landscape
    [[ ${SKIP_TO_PHASE} -le 6 ]] && backend_install_docker
    [[ ${SKIP_TO_PHASE} -le 7 ]] && phase_cleanup_and_shrink
    phase_report
}

main
