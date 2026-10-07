#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  install.sh — link these dotfiles into $HOME
#
#  Uses symlinks rather than copies so that editing the repo file
#  takes effect immediately (no re-install needed) and git stays
#  the single source of truth.
#
#  Safe to run repeatedly. Anything it would overwrite is first
#  copied to  $HOME/.dotfiles-backup/<timestamp>/.
#
#  Usage:
#    ./install.sh            link everything
#    ./install.sh --dry-run  show what would happen
#    ./install.sh --force    overwrite without keeping a backup
#
#  Run as yourself, NOT with sudo — sudo would root-own your dotfiles.
# ─────────────────────────────────────────────────────────────
set -uo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DRY=0; FORCE=0
BACKUP_ROOT="$HOME/.dotfiles-backup"
STAMP=$(date +%Y%m%d-%H%M%S)

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --force)   FORCE=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'unknown option: %s\n' "$arg" >&2; exit 64 ;;
  esac
done

# refuse sudo: it would create root-owned files in your home
if [ "$(id -u)" -eq 0 ]; then
  echo "Don't run this with sudo — it would root-own your dotfiles." >&2
  echo "Re-run as your normal user." >&2
  exit 1
fi

if [ -t 1 ]; then
  G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[1m'; R=$'\033[0m'; Dim=$'\033[2m'
else
  G=''; Y=''; B=''; R=''; Dim=''
fi

# Each entry: <source in repo> -> <destination in $HOME>
# Col 1 is relative to REPO_DIR, col 2 is relative to $HOME.
TARGETS=(
  ".bashrc        .bashrc"
  "bin/play       bin/play"
  "bin/laptop-health.sh bin/laptop-health.sh"
)

linked=0; backed=0; skipped=0

run() {  # run <cmd...> — honours --dry-run
  if [ "$DRY" = "1" ]; then echo "  ${Dim}(dry-run) $*${R}"; else "$@"; fi
}

backup_path() {
  local dest=$1
  mkdir -p "$BACKUP_ROOT/$STAMP"
  run cp -a "$dest" "$BACKUP_ROOT/$STAMP/"
  backed=$((backed + 1))
  echo "  ${Y}!${R} backed up -> $BACKUP_ROOT/$STAMP/$(basename "$dest")"
}

printf '%sLinking dotfiles%s  %s -> %s\n\n' "$B" "$R" "$REPO_DIR" "$HOME"

for entry in "${TARGETS[@]}"; do
  # shellcheck disable=SC2086
  set -- $entry
  src="$REPO_DIR/$1"; dest="$HOME/$2"

  [ -e "$src" ] || { echo "  ${Y}!${R} source missing: $1 (skipped)"; skipped=$((skipped+1)); continue; }

  # Already correct? — idempotent no-op.
  if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
    echo "  ${G}✓${R} $2 (already linked)"
    skipped=$((skipped+1)); continue
  fi

  # Something else is there — back it up first unless --force.
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$FORCE" = "1" ]; then
      run rm -rf "$dest"
      echo "  ${Y}!${R} $2 replaced (--force, no backup)"
    else
      backup_path "$dest"
      run rm -rf "$dest"
    fi
  fi

  mkdir -p "$(dirname "$dest")"
  run ln -s "$src" "$dest"
  if [ "$DRY" = "1" ]; then
    echo "  ${Dim}~${R} $2 -> $1 (dry-run)"
  else
    [ -L "$dest" ] && echo "  ${G}✓${R} $2 -> $1" || { echo "  ✗ failed: $2"; exit 1; }
  fi
  linked=$((linked + 1))
done

echo
printf '%sSummary:%s %d linked, %d unchanged, %d backed up\n' \
  "$B" "$R" "$linked" "$skipped" "$backed"

if [ "$backed" -gt 0 ] && [ "$DRY" != "1" ]; then
  printf '%sPrevious files saved in %s/%s%s\n' "$Dim" "$BACKUP_ROOT" "$STAMP" "$R"
fi

echo
printf '%sNext steps:%s\n' "$B" "$R"
printf '  source ~/.bashrc      # or open a new terminal\n'
printf '  health                # run the health report\n'
printf '  play <song name>      # needs: sudo apt install yt-dlp mpv\n'
exit 0
