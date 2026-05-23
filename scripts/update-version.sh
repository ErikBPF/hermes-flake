#!/usr/bin/env bash
# Hourly auto-updater for hermes-flake. Polls upstream NousResearch/hermes-agent
# for the latest tagged release, bumps flake.nix + flake.lock, verifies the
# build, then exits. Returns:
#   0 — no update needed (already current)
#   0 — update applied (and verified) when not --check-only
#   1 — update available (when --check-only)
#   2 — error
set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

readonly UPSTREAM_REPO="NousResearch/hermes-agent"
readonly UPSTREAM_API="https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest"

log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

ensure_in_repository_root() {
    if [ ! -f flake.nix ]; then
        log_error "flake.nix not found. Run from the repository root."
        exit 2
    fi
}

ensure_required_tools_installed() {
    for cmd in nix curl sed grep; do
        command -v "$cmd" >/dev/null 2>&1 || {
            log_error "$cmd is required but not installed."
            exit 2
        }
    done
}

# Read current pin from flake.nix — matches:
#   url = "github:NousResearch/hermes-agent/v2026.5.16";
get_current_version() {
    sed -n 's|.*github:NousResearch/hermes-agent/\([^"]*\)".*|\1|p' flake.nix | head -1
}

# Fetch latest release tag from upstream
get_latest_version() {
    curl -sf --max-time 15 "$UPSTREAM_API" \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' \
        | head -1
}

update_flake_pin() {
    local new_version="$1"
    # Update the github:<repo>/<ref> ref in flake.nix
    sed -i.bak "s|github:NousResearch/hermes-agent/[^\"]*|github:NousResearch/hermes-agent/${new_version}|" flake.nix
    rm -f flake.nix.bak
}

update_flake_lock() {
    log_info "Updating flake.lock for hermes-agent-src..."
    nix flake update hermes-agent-src
}

verify_build() {
    log_info "Verifying build..."
    if ! nix build .#hermes-agent --no-link >/dev/null 2>&1; then
        log_error "Build failed for the new pin"
        return 1
    fi
    log_info "Build successful."
}

verify_smoke() {
    log_info "Running smoke check..."
    if ! nix build .#checks."$(nix eval --raw --impure --expr 'builtins.currentSystem')".smoke --no-link >/dev/null 2>&1; then
        log_warn "Smoke check failed (might just be transient — re-run manually)."
        return 1
    fi
    log_info "Smoke check passed."
}

show_changes() {
    git diff --stat flake.nix flake.lock 2>/dev/null || true
}

print_usage() {
    cat <<USAGE
Usage: $0 [OPTIONS]

Options:
  --check          Print current vs latest; exit 1 if an update is available
  --version VER    Pin to a specific upstream release tag (e.g. v2026.5.16)
  --help           Show this message

Examples:
  $0                       # Update to latest upstream release
  $0 --check               # Detect whether an update is available
  $0 --version v2026.5.16  # Pin a specific release
USAGE
}

main() {
    local target_version=""
    local check_only=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check) check_only=true; shift ;;
            --version) target_version="$2"; shift 2 ;;
            --help) print_usage; exit 0 ;;
            *) log_error "Unknown option: $1"; print_usage; exit 2 ;;
        esac
    done

    ensure_in_repository_root
    ensure_required_tools_installed

    local current latest
    current=$(get_current_version)
    if [ -z "$current" ]; then
        log_error "Couldn't parse current hermes-agent pin from flake.nix"
        exit 2
    fi

    if [ -n "$target_version" ]; then
        latest="$target_version"
    else
        latest=$(get_latest_version)
        if [ -z "$latest" ]; then
            log_error "Couldn't fetch latest release from upstream"
            exit 2
        fi
    fi

    log_info "Current pin:    $current"
    log_info "Latest upstream: $latest"

    if [ "$current" = "$latest" ]; then
        log_info "Already up to date."
        exit 0
    fi

    if [ "$check_only" = true ]; then
        log_info "Update available: $current → $latest"
        exit 1
    fi

    update_flake_pin "$latest"
    update_flake_lock
    verify_build || { git checkout flake.nix flake.lock; exit 2; }
    verify_smoke || log_warn "Smoke regression — review before merging"

    log_info "Updated hermes-agent pin: $current → $latest"
    show_changes
}

main "$@"
