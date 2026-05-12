#!/usr/bin/env bash
# Internal installer for Claude Provider Router. Use `bin/burnkit install router`.
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DRY_RUN=0

usage() {
    cat <<'EOF'
Claude Provider Router installer

Usage:
  bin/burnkit install router [--dry-run]

This creates tools/claude-provider-router/config.env from config.env.example
when it is missing. Existing config.env is preserved byte-for-byte.
It also installs a c shim into ~/.local/bin when that path is available.
EOF
}

log() {
    printf '%s\n' "$*"
}

ok() {
    printf 'OK  %s\n' "$1"
}

warn() {
    printf 'WARN %s\n' "$1"
}

die() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

require_file() {
    [ -f "$1" ] || die "missing file: $1"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            -h|--help) usage; exit 0 ;;
            *) die "unknown router install option: $1" ;;
        esac
        shift
    done
}

install_c_shim() {
    local shim_dir="${BURNKIT_C_SHIM_DIR:-$HOME/.local/bin}"
    local shim="$shim_dir/c"
    local target="$SCRIPT_DIR/c"

    if [ -L "$shim" ] && [ "$(readlink "$shim")" = "$target" ]; then
        ok "c shim already installed: $shim"
        return 0
    fi

    if [ -e "$shim" ]; then
        warn "c command already exists and is not a managed shim: $shim"
        warn "skipping c shim; run directly with: $target"
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would install c shim: $shim -> $target"
        return 0
    fi

    mkdir -p "$shim_dir"
    ln -sf "$target" "$shim"
    ok "installed c shim: $shim -> $target"

    case ":${PATH}:" in
        *":$shim_dir:"*) ;;
        *) warn "add $shim_dir to PATH to use: c 0" ;;
    esac
}

main() {
    parse_args "$@"

    local example="$SCRIPT_DIR/config.env.example"
    local target="$SCRIPT_DIR/config.env"
    require_file "$SCRIPT_DIR/c"
    require_file "$example"

    if [ -f "$target" ]; then
        ok "router config already exists: $target"
    elif [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] would copy $example -> $target"
        log "[dry-run] would chmod 600 $target"
    else
        cp "$example" "$target"
        chmod 600 "$target"
        ok "created router config: $target"
        log "WARN edit $target before running: c 0"
    fi

    install_c_shim
}

main "$@"
