#!/bin/sh
# lfs-scripts bootstrap - ncurses/dialog front-end.
#
# The build logic lives in files/bootstrap-core.sh (temporary toolchain, base
# system, rebuild, rootfs compression). This script only collects settings and
# drives those stages, so the interactive and scripted paths run exactly the
# same code.
#
# Usage:
#   ./bootstrap.sh                 interactive dialog menu
#   ./bootstrap.sh 1|2|3|4         run a stage directly (text mode)
#   ./bootstrap.sh --settings      edit settings, save to bootstrap.conf
#   ./bootstrap.sh --help
set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CORE="$SCRIPT_DIR/files/bootstrap-core.sh"
CONF="$SCRIPT_DIR/bootstrap.conf"
BACKTITLE="lfs-scripts bootstrap"

[ -f "$CORE" ] || {
    echo "error: $CORE is missing" >&2
    exit 1
}

# ---------------------------------------------------------------- settings ---
# Defaults can be overridden by environment or bootstrap.conf.
: "${LFS:=/tmp/lfs-rootfs}"
: "${TOOLS:=/tmp/lfs-tools}"
: "${SOURCEDIR:=$SCRIPT_DIR/sources}"
: "${PACKAGESDIR:=$SCRIPT_DIR/packages}"
: "${BFS_JOBS:=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"

if [ -f "$CONF" ]; then
    # shellcheck disable=SC1090
    . "$CONF"
fi

save_settings() {
    cat > "$CONF" <<EOF
# written by bootstrap.sh -- edit freely, or use the Settings menu
LFS=$LFS
TOOLS=$TOOLS
SOURCEDIR=$SOURCEDIR
PACKAGESDIR=$PACKAGESDIR
BFS_JOBS=$BFS_JOBS
EOF
}

# ------------------------------------------------------------------ dialog ---
DIALOG_BIN=""
detect_dialog() {
    if command -v dialog >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]; then
        DIALOG_BIN=dialog
    elif command -v whiptail >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]; then
        DIALOG_BIN=whiptail
    fi
}

ui_info() {
    if [ -n "$DIALOG_BIN" ]; then
        "$DIALOG_BIN" --backtitle "$BACKTITLE" --title "$1" --msgbox "$2" 12 72
    else
        printf '\n== %s ==\n%s\n\n' "$1" "$2" >&2
    fi
}

ui_error() {
    if [ -n "$DIALOG_BIN" ]; then
        "$DIALOG_BIN" --backtitle "$BACKTITLE" --title "${1:-Error}" \
            --msgbox "${2:-Operation failed. See the log.}" 12 72
    else
        printf 'ERROR: %s\n' "${2:-${1:-operation failed}}" >&2
    fi
}

ui_yesno() {
    if [ -n "$DIALOG_BIN" ]; then
        "$DIALOG_BIN" --backtitle "$BACKTITLE" --title "$1" --yesno "$2" 12 72
    else
        printf '%s\n%s [y/N] ' "$1" "$2" >&2
        read -r reply
        case $reply in [yY]*) return 0 ;; *) return 1 ;; esac
    fi
}

ui_input() {
    prompt=$1
    current=$2
    if [ -n "$DIALOG_BIN" ]; then
        "$DIALOG_BIN" --backtitle "$BACKTITLE" --title "$prompt" \
            --inputbox "$prompt" 10 72 "$current" 3>&1 1>&2 2>&3
    else
        printf '%s [%s]: ' "$prompt" "$current" >&2
        read -r answer
        [ -n "$answer" ] && printf '%s\n' "$answer" || printf '%s\n' "$current"
    fi
}

ui_menu() {
    title=$1
    shift
    if [ -n "$DIALOG_BIN" ]; then
        "$DIALOG_BIN" --backtitle "$BACKTITLE" --title "$title" \
            --cancel-button "Back" --menu "Select an action" 0 0 0 "$@" \
            3>&1 1>&2 2>&3
    else
        printf '\n== %s ==\n' "$title" >&2
        printf '%s\n' "$@" >&2
        printf 'Choice: ' >&2
        read -r answer
        printf '%s\n' "$answer"
    fi
}

# ---------------------------------------------------------------- actions ----
run_stage() {
    stage=$1
    label=$2
    mkdir -p "$SCRIPT_DIR/logs"
    log="$SCRIPT_DIR/logs/bootstrap-$(date +%Y%m%d-%H%M%S)-stage$stage.log"

    if [ "$stage" = 2 ] && [ "$(id -u)" != 0 ]; then
        ui_error "Root required" "Building the base system needs root. Re-run with sudo."
        return 1
    fi
    if [ "$stage" = 1 ] && [ "$(id -u)" = 0 ]; then
        ui_error "Regular user required" \
            "The temporary toolchain must be built as a regular user, not root."
        return 1
    fi

    ui_yesno "$label" "Run: $label

LFS:         $LFS
TOOLS:       $TOOLS
Sources:     $SOURCEDIR
Packages:    $PACKAGESDIR
Jobs:        $BFS_JOBS

Log: $log" || return 1

    rc=0
    (
        export LFS TOOLS SOURCEDIR PACKAGESDIR
        export MAKEFLAGS="-j$BFS_JOBS"
        cd "$SCRIPT_DIR"
        sh "$CORE" "$stage"
    ) 2>&1 | tee "$log" || rc=$?

    if [ "$rc" -eq 0 ]; then
        ui_info "$label" "Finished.

Log: $log"
    else
        ui_error "$label failed" "Exit status $rc. See $log"
        return 1
    fi
}

settings_menu() {
    while :; do
        choice=$(ui_menu "Settings" \
            LFS "Installation root: $LFS" \
            TOOLS "Temporary toolchain: $TOOLS" \
            SOURCES "Source cache: $SOURCEDIR" \
            PACKAGES "Package cache: $PACKAGESDIR" \
            JOBS "Parallel jobs: $BFS_JOBS" \
            SAVE "Save to bootstrap.conf" \
            BACK "Return to the main menu") || return 0

        case $choice in
            LFS)      LFS=$(ui_input "Installation root (LFS)" "$LFS") ;;
            TOOLS)    TOOLS=$(ui_input "Temporary toolchain (TOOLS)" "$TOOLS") ;;
            SOURCES)  SOURCEDIR=$(ui_input "Source cache directory" "$SOURCEDIR") ;;
            PACKAGES) PACKAGESDIR=$(ui_input "Package cache directory" "$PACKAGESDIR") ;;
            JOBS)     BFS_JOBS=$(ui_input "Parallel jobs" "$BFS_JOBS") ;;
            SAVE)     save_settings; ui_info "Saved" "$CONF updated." ;;
            BACK|"")  return 0 ;;
        esac
    done
}

main_menu() {
    while :; do
        choice=$(ui_menu "lfs-scripts bootstrap" \
            TOOLCHAIN "Build the temporary toolchain (regular user)" \
            BASE "Build the base system (root)" \
            REBUILD "Rebuild the base system (root)" \
            COMPRESS "Compress the finished rootfs" \
            SETTINGS "Settings" \
            QUIT "Quit") || choice=QUIT

        case $choice in
            TOOLCHAIN) run_stage 1 "Temporary toolchain" ;;
            BASE)      run_stage 2 "Base system" ;;
            REBUILD)   run_stage 3 "Rebuild base system" ;;
            COMPRESS)  run_stage 4 "Compress rootfs" ;;
            SETTINGS)  settings_menu ;;
            QUIT|"")   return 0 ;;
        esac
    done
}

usage() {
    cat <<EOF
Usage: $0 [option]

  (no option)     interactive ncurses/dialog menu
  1               build the temporary toolchain (regular user)
  2               build the base system (root)
  3               rebuild the base system (root)
  4               compress the finished rootfs
  --settings      edit settings and save them to bootstrap.conf
  --text          skip the dialog menu and prompt in plain text
  --help          this message

Settings come from the environment, then bootstrap.conf:
  LFS, TOOLS, SOURCEDIR, PACKAGESDIR, BFS_JOBS
EOF
}

case ${1:-} in
    1|2|3|4)
        detect_dialog
        DIALOG_BIN=""
        run_stage "$1" "stage $1"
        ;;
    --settings)
        detect_dialog
        settings_menu
        ;;
    --text)
        detect_dialog
        DIALOG_BIN=""
        main_menu
        ;;
    -h|--help)
        usage
        ;;
    "")
        detect_dialog
        if [ -z "$DIALOG_BIN" ]; then
            printf 'dialog/whiptail not found on a terminal; using text prompts.\n' >&2
        fi
        main_menu
        ;;
    *)
        usage
        exit 2
        ;;
esac

exit 0
