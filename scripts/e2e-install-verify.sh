#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="dry-run"
RUN_ROUTER=1
RUN_TABS=1
RUN_BURN=1

usage() {
    cat <<'EOF'
BurnKit end-to-end install verifier

Default mode is safe dry-run. It does not modify user Claude/Codex/launchd/SwiftBar state.

Usage:
  scripts/e2e-install-verify.sh [--dry-run]
  scripts/e2e-install-verify.sh --real [--skip-router] [--skip-tabs] [--skip-burn]

Checks:
  - burnkit entrypoint syntax and help
  - router config.env preservation when config.env already exists
  - dry-run install flows for router, tabs, burn, and all
  - real install postconditions when --real is explicit

Real mode modifies local machine state:
  - tools/claude-provider-router/config.env
  - ~/.claude/hooks and ~/.codex/hooks
  - ~/.claude/settings.json and ~/.codex/hooks.json
  - ~/Library/LaunchAgents
  - ~/.burn-ai
  - ~/.local/bin/burn-ai
  - SwiftBar plugin directory
EOF
}

log() {
    printf '%s\n' "$*"
}

section() {
    printf '\n%s\n' "$1"
    printf '%s\n' "========================================"
}

pass() {
    printf 'PASS %s\n' "$1"
}

note() {
    printf 'NOTE %s\n' "$1"
}

fail() {
    printf 'FAIL %s\n' "$1" >&2
    exit 1
}

run() {
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    "$@"
}

sha256_file() {
    shasum -a 256 "$1" | awk '{print $1}'
}

assert_file() {
    [ -f "$1" ] || fail "missing file: $1"
}

assert_executable() {
    [ -x "$1" ] || fail "missing executable: $1"
}

assert_symlink_target() {
    local link="$1"
    local expected="$2"
    [ -L "$link" ] || fail "missing symlink: $link"
    local actual
    actual="$(readlink "$link")"
    [ "$actual" = "$expected" ] || fail "wrong symlink target for $link: $actual != $expected"
}

assert_file_copy() {
    local file="$1"
    local expected="$2"
    [ -f "$file" ] || fail "missing file: $file"
    [ ! -L "$file" ] || fail "expected real file, got symlink: $file"
    cmp -s "$expected" "$file" || fail "file content differs: $file != $expected"
}

assert_launchd_loaded() {
    local label="$1"
    launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 || fail "launchd job is not loaded: $label"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --dry-run) MODE="dry-run" ;;
            --real) MODE="real" ;;
            --skip-router) RUN_ROUTER=0 ;;
            --skip-tabs) RUN_TABS=0 ;;
            --skip-burn) RUN_BURN=0 ;;
            -h|--help) usage; exit 0 ;;
            *) fail "unknown argument: $1" ;;
        esac
        shift
    done
}

verify_entrypoint() {
    section "Entrypoint"
    run bash -n "$REPO_ROOT/bin/burnkit"
    run "$REPO_ROOT/bin/burnkit" --help >/dev/null
    pass "bin/burnkit syntax and help"
}

verify_router_config_preservation() {
    section "Router config.env preservation"
    local temp_dir
    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/burnkit-router-preserve.XXXXXX")"

    mkdir -p "$temp_dir/bin" "$temp_dir/tools/claude-provider-router"
    cp "$REPO_ROOT/bin/burnkit" "$temp_dir/bin/burnkit"
    cp "$REPO_ROOT/tools/claude-provider-router/c" "$temp_dir/tools/claude-provider-router/c"
    cp "$REPO_ROOT/tools/claude-provider-router/install-core.sh" "$temp_dir/tools/claude-provider-router/install-core.sh"
    cp "$REPO_ROOT/tools/claude-provider-router/config.env.example" "$temp_dir/tools/claude-provider-router/config.env.example"
    chmod +x "$temp_dir/bin/burnkit" "$temp_dir/tools/claude-provider-router/c" "$temp_dir/tools/claude-provider-router/install-core.sh"

    local config="$temp_dir/tools/claude-provider-router/config.env"
    cat > "$config" <<'EOF'
CONFIG_0_BASE_URL=https://custom.example.invalid/anthropic
CONFIG_0_AUTH_TOKEN=do-not-overwrite-this-token
CONFIG_0_MODEL=custom-model
EOF
    chmod 600 "$config"

    local before_hash after_hash before_mode after_mode
    before_hash="$(sha256_file "$config")"
    before_mode="$(stat -f '%Lp' "$config")"

    run "$temp_dir/bin/burnkit" install router >/dev/null

    after_hash="$(sha256_file "$config")"
    after_mode="$(stat -f '%Lp' "$config")"
    [ "$before_hash" = "$after_hash" ] || fail "existing config.env was modified"
    [ "$before_mode" = "$after_mode" ] || fail "existing config.env mode changed: $before_mode -> $after_mode"
    grep -q "do-not-overwrite-this-token" "$config" || fail "sentinel token missing after router install"
    rm -rf "$temp_dir"
    pass "existing config.env is preserved byte-for-byte"
}

verify_router_config_creation() {
    section "Router config.env creation"
    local temp_dir
    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/burnkit-router-create.XXXXXX")"

    mkdir -p "$temp_dir/bin" "$temp_dir/tools/claude-provider-router"
    cp "$REPO_ROOT/bin/burnkit" "$temp_dir/bin/burnkit"
    cp "$REPO_ROOT/tools/claude-provider-router/c" "$temp_dir/tools/claude-provider-router/c"
    cp "$REPO_ROOT/tools/claude-provider-router/install-core.sh" "$temp_dir/tools/claude-provider-router/install-core.sh"
    cp "$REPO_ROOT/tools/claude-provider-router/config.env.example" "$temp_dir/tools/claude-provider-router/config.env.example"
    chmod +x "$temp_dir/bin/burnkit" "$temp_dir/tools/claude-provider-router/c" "$temp_dir/tools/claude-provider-router/install-core.sh"

    local config="$temp_dir/tools/claude-provider-router/config.env"
    run "$temp_dir/bin/burnkit" install router >/dev/null

    assert_file "$config"
    [ "$(stat -f '%Lp' "$config")" = "600" ] || fail "created config.env mode is not 600"
    cmp -s "$temp_dir/tools/claude-provider-router/config.env.example" "$config" || fail "created config.env does not match template"
    rm -rf "$temp_dir"
    pass "missing config.env is created from template with mode 600"
}

verify_dry_run_installs() {
    section "Dry-run install flows"
    run "$REPO_ROOT/bin/burnkit" install router --dry-run >/dev/null
    run "$REPO_ROOT/bin/burnkit" install tabs --dry-run --skip-python-check >/dev/null
    run "$REPO_ROOT/bin/burnkit" install burn --dry-run >/dev/null
    run "$REPO_ROOT/bin/burnkit" install all --dry-run --skip-python-check >/dev/null
    pass "dry-run install flows completed"
}

verify_real_router() {
    [ "$RUN_ROUTER" -eq 1 ] || return 0
    section "Real router install"
    local config="$REPO_ROOT/tools/claude-provider-router/config.env"
    local before_hash=""
    local existed=0
    if [ -f "$config" ]; then
        existed=1
        before_hash="$(sha256_file "$config")"
        note "existing config.env detected; verifier will require it to remain unchanged"
    fi

    run "$REPO_ROOT/bin/burnkit" install router
    assert_file "$config"
    [ "$(stat -f '%Lp' "$config")" = "600" ] || fail "config.env mode is not 600"
    if [ "$existed" -eq 1 ]; then
        local after_hash
        after_hash="$(sha256_file "$config")"
        [ "$before_hash" = "$after_hash" ] || fail "real router install modified existing config.env"
        pass "real router install preserved existing config.env"
    else
        pass "real router install created config.env with mode 600"
    fi
}

verify_real_tabs() {
    [ "$RUN_TABS" -eq 1 ] || return 0
    section "Real iTerm2 Tab Color install"
    run "$REPO_ROOT/bin/burnkit" install tabs
    assert_file_copy "$HOME/.claude/hooks/tab_color_hook.sh" "$REPO_ROOT/tools/iterm2-tab-color/tab_color_hook.sh"
    assert_file_copy "$HOME/.codex/hooks/tab_color_hook.sh" "$REPO_ROOT/tools/iterm2-tab-color/tab_color_hook.sh"
    assert_file "$HOME/Library/LaunchAgents/com.duying.tab-color-daemon.plist"
    [ ! -L "$HOME/Library/LaunchAgents/com.duying.tab-color-daemon.plist" ] || fail "tab color plist must be a real file, not a symlink"
    assert_launchd_loaded "com.duying.tab-color-daemon"
    pass "real tab color install postconditions"
}

verify_real_burn() {
    [ "$RUN_BURN" -eq 1 ] || return 0
    section "Real Burn AI install"
    run "$REPO_ROOT/bin/burnkit" install burn
    assert_file "$HOME/.burn-ai/app/dist/cli.js"
    assert_executable "$HOME/.burn-ai/app/dist/cli.js"
    assert_symlink_target "$HOME/.local/bin/burn-ai" "$HOME/.burn-ai/app/dist/cli.js"
    assert_file "$HOME/Library/LaunchAgents/com.duying.burn-ai.plist"
    assert_launchd_loaded "com.duying.burn-ai"
    run "$HOME/.local/bin/burn-ai" doctor
    run "$HOME/.local/bin/burn-ai" status --refresh
    run "$HOME/.local/bin/burn-ai" menubar render >/dev/null
    pass "real Burn AI install postconditions"
}

main() {
    parse_args "$@"
    section "BurnKit install verification mode: $MODE"
    verify_entrypoint
    verify_router_config_preservation
    verify_router_config_creation

    if [ "$MODE" = "dry-run" ]; then
        verify_dry_run_installs
    else
        verify_real_router
        verify_real_tabs
        verify_real_burn
    fi

    section "Result"
    pass "BurnKit install verification completed"
}

main "$@"
