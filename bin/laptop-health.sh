#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  laptop-health.sh — one-shot system health report
#
#  Prints a compact pass/fail summary of CPU temp, RAM, swap,
#  SSD SMART health, battery, disk usage and the protective
#  services (zram / earlyoom / noc-monitor).
#
#  Usage:
#    laptop-health.sh           full report
#    laptop-health.sh --brief   one-line verdict only
#    laptop-health.sh --json    machine-readable (for scripts)
#
#  Exit code: 0 = all green, 1 = something needs attention,
#             2 = critical condition found.
# ─────────────────────────────────────────────────────────────
set -uo pipefail

# ── presentation helpers ─────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\033[0m'; B=$'\033[1m'; G=$'\033[32m'
  Y=$'\033[33m'; Rd=$'\033[31m'; Dim=$'\033[2m'
else
  R=''; B=''; G=''; Y=''; Rd=''; Dim=''
fi

WARN=0   # count of warnings
CRIT=0   # count of criticals

pass() { printf '  %s✓%s %-22s %s\n' "$G" "$R" "$1" "$2"; }
warn() { printf '  %s!%s %-22s %s\n' "$Y" "$R" "$1" "$2"; WARN=$((WARN + 1)); }
fail() { printf '  %s✗%s %-22s %s\n' "$Rd" "$R" "$1" "$2"; CRIT=$((CRIT + 1)); }
section() { printf '\n%s%s%s\n' "$B" "$1" "$R"; }
rule() { printf '%s%s%s\n' "$Dim" "──────────────────────────────────────────" "$R"; }

# ── arguments ────────────────────────────────────────────────
BRIEF=0; JSON=0
for a in "$@"; do
  case "$a" in
    --brief) BRIEF=1 ;;
    --json)  JSON=1 ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) printf 'unknown option: %s\n' "$a" >&2; exit 64 ;;
  esac
done

# ── collectors (each degrades gracefully if unavailable) ─────
CORES=$(nproc 2>/dev/null || echo 1)
BAT=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
SMART=$(sudo -n /usr/sbin/nvme smart-log /dev/nvme0 2>/dev/null)
LOG=${HOME}/.local/state/noc-monitor.log

# temperature: first label found across Intel / AMD / NVIDIA
read_cpu_temp() {
  sensors 2>/dev/null | awk '
    /^[^ \t:]+[ \t]*$/ { c=$1; next }
    ($1=="Tctl:" || $1=="Package" || $1=="Core") && c ~ /k10temp|coretemp|zenpower/ {
      v=$NF; gsub(/[^0-9.+-]/,"",v); print v; exit
    }' | head -1
}
read_gpu_temp() {
  sensors 2>/dev/null | awk '
    /^[^ \t:]+[ \t]*$/ { c=$1; next }
    $1=="edge:" || $1=="temp1:" { if (c ~ /amdgpu|nvidia/) { v=$2; gsub(/[^0-9.+-]/,"",v); print v; exit } }'
}
smart_field() { awk -v k="$1" 'tolower($0) ~ k { gsub(/[^0-9]/,"",$NF); print $NF; exit }' <<< "$SMART"; }

# ── checks ───────────────────────────────────────────────────
check_temp() {
  section "TEMPERATURE"
  local t
  t=$(read_cpu_temp)
  if [ -z "$t" ]; then
    warn "CPU temperature" "sensor not readable"
  elif awk "BEGIN{exit !($t >= 90)}"; then
    fail "CPU temperature" "${t}°C  (critical >= 90°C)"
  elif awk "BEGIN{exit !($t >= 75)}"; then
    warn "CPU temperature" "${t}°C  (warm, ok if under load)"
  else
    pass "CPU temperature" "${t}°C"
  fi
  t=$(read_gpu_temp)
  [ -n "$t" ] && pass "GPU temperature" "${t}°C"
}

check_ram() {
  section "MEMORY & SWAP"
  local used avail swapfree swaptotal
  used=$(free -m | awk '/^Mem:/{print $3}')
  avail=$(free -m | awk '/^Mem:/{print $7}')
  swaptotal=$(free -m | awk '/^Swap:/{print $2}')
  swapfree=$(free -m | awk '/^Swap:/{print $4}')

  if [ "$avail" -lt 300 ]; then
    fail "Available RAM" "${avail} MB  (critical < 300 MB)"
  elif [ "$avail" -lt 800 ]; then
    warn "Available RAM" "${avail} MB  (low)"
  else
    pass "Available RAM" "${avail} MB free, ${used} MB used"
  fi

  if [ "${swaptotal:-0}" -gt 0 ]; then
    local used_pct=$(( (swaptotal - swapfree) * 100 / swaptotal ))
    if [ "$used_pct" -ge 90 ]; then
      fail "Swap usage" "${used_pct}% of ${swaptotal} MB used"
    elif [ "$used_pct" -ge 70 ]; then
      warn "Swap usage" "${used_pct}% of ${swaptotal} MB"
    else
      pass "Swap" "${swaptotal} MB total, ${used_pct}% used"
    fi
    swapon --show -no NAME,PRIO 2>/dev/null | while read -r n p; do
      [ -n "$n" ] && pass "  swap device" "$n (priority $p)"
    done
  else
    warn "Swap" "none configured — RAM full will freeze the machine"
  fi
}

check_ssd() {
  section "STORAGE"
  if [ -z "$SMART" ]; then
    warn "SSD SMART" "cannot read (needs sudo or nvme-cli)"
    return
  fi
  local life warn0 media temp
  life=$(( 100 - $(smart_field 'percentage_used') ))
  warn0=$(smart_field 'critical_warning')
  media=$(smart_field 'media_errors')
  temp=$(smart_field '^temperature')

  if [ "$warn0" != "0" ]; then
    fail "SSD critical warning" "NVMe reports an alert — back up NOW"
  elif [ "$media" -gt 0 ] 2>/dev/null; then
    fail "SSD media errors" "${media} errors — drive may be failing"
  elif [ "$life" -le 10 ]; then
    fail "SSD life left" "${life}% — replace soon"
  elif [ "$life" -le 25 ]; then
    warn "SSD life left" "${life}% — plan a replacement"
  else
    pass "SSD health" "${life}% life, ${media:-0} errors"
  fi
  [ -n "$temp" ] && pass "SSD temperature" "${temp}°C"

  local usage
  usage=$(df -P / 2>/dev/null | awk 'NR==2{gsub(/%/,"");print $5}')
  if [ -n "$usage" ]; then
    if [ "$usage" -ge 93 ]; then fail "Root filesystem" "${usage}% full"
    elif [ "$usage" -ge 85 ]; then warn "Root filesystem" "${usage}% full"
    else pass "Root filesystem" "${usage}% used ($(df -h / | awk 'NR==2{print $4}') free)"
    fi
  fi
}

check_battery() {
  section "BATTERY"
  if [ -z "${BAT:-}" ]; then
    warn "Battery" "not detected"
    return
  fi
  local pct status chargefull nowfull
  pct=$(cat "$BAT/capacity" 2>/dev/null || echo 0)
  status=$(cat "$BAT/status" 2>/dev/null || echo Unknown)
  if [ "$pct" -le 10 ]; then
    fail "Battery level" "${pct}% ($status) — plug in now"
  elif [ "$pct" -le 20 ]; then
    warn "Battery level" "${pct}% ($status)"
  else
    pass "Battery level" "${pct}% ($status)"
  fi

  # Real health = full design capacity ratio (0-100%)
  if [ -r "$BAT/energy_full" ] && [ -r "$BAT/energy_full_design" ]; then
    chargefull=$(cat "$BAT/energy_full"); nowfull=$(cat "$BAT/energy_full_design")
    [ "$nowfull" -gt 0 ] 2>/dev/null && local h=$(( chargefull * 100 / nowfull )) \
      && { [ "$h" -le 70 ] && fail "Battery health" "${h}% of design capacity" \
        || { [ "$h" -le 85 ] && warn "Battery health" "${h}%" || pass "Battery health" "${h}% of design"; }; }
  fi
}

check_services() {
  section "PROTECTIVE SERVICES"
  local s a e
  for s in zram-swap earlyoom; do
    a=$(systemctl is-active "$s" 2>/dev/null)
    e=$(systemctl is-enabled "$s" 2>/dev/null)
    if [ "$a" = "active" ] && [ "$e" = "enabled" ]; then
      pass "$s" "active, enabled at boot"
    elif [ "$a" = "active" ]; then
      warn "$s" "running but NOT enabled at boot"
    else
      fail "$s" "not running ($a)"
    fi
  done
  a=$(systemctl --user is-active noc-monitor 2>/dev/null)
  e=$(systemctl --user is-enabled noc-monitor 2>/dev/null)
  if [ "$a" = "active" ] && [ "$e" = "enabled" ]; then
    pass "noc-monitor" "active, enabled at boot"
  elif [ "$a" = "active" ]; then
    warn "noc-monitor" "running but NOT enabled at boot"
  else
    fail "noc-monitor" "not running ($a)"
  fi

  # The monitor appends a sample every CHECK_INTERVAL, so the log
  # file's mtime IS the heartbeat. Using stat here rather than
  # parsing the HH:MM:SS inside the line avoids TZ/date arithmetic.
  if [ -r "$LOG" ]; then
    local age now mtime
    now=$(date +%s)
    mtime=$(stat -c %Y "$LOG" 2>/dev/null || echo 0)
    age=$(( now - mtime ))
    if [ "$age" -le 120 ]; then
      pass "monitor heartbeat" "last sample ${age}s ago"
    else
      warn "monitor heartbeat" "stale — last write ${age}s ago"
    fi
  else
    warn "monitor heartbeat" "no log file yet"
  fi
}

check_errors() {
  section "RECENT ERRORS"
  local oom failed
  oom=$(journalctl -k -b 0 2>/dev/null | grep -ciE 'oom-kill|out of memory' || true)
  if [ "$oom" -gt 0 ]; then
    fail "OOM kills this boot" "${oom} — RAM ran out"
  else
    pass "OOM kills this boot" "none"
  fi
  failed=$(systemctl --failed --no-qr 2>/dev/null | grep -c '^' || true)
  # casper-md5check is a Live-ISO leftover and is expected to fail
  local real
  real=$(systemctl --failed --no-qr 2>/dev/null | grep -v 'casper-md5check' | grep -c '^' || true)
  if [ "${real:-0}" -gt 0 ]; then
    warn "Failed services" "${real} failed ($(systemctl --failed --no-qr | grep -v casper | awk '{print $1}' | tr '\n' ' '))"
  else
    pass "Failed services" "none (ignoring casper-md5check)"
  fi
}

# ── output modes ─────────────────────────────────────────────
if [ "$JSON" = "1" ]; then
  # machine-readable: reuse the collectors, emit key=value JSON
  c=$(read_cpu_temp); g=$(read_gpu_temp)
  a=$(free -m | awk '/^Mem:/{print $7}')
  st=$(free -m | awk '/^Swap:/{print $2}')
  life=""; media=""; bpct=""
  if [ -n "$SMART" ]; then
    # percentage_used is how much life is GONE; report life REMAINING.
    local_used=$(smart_field 'percentage_used')
    [ -n "$local_used" ] && life=$(( 100 - local_used ))
    media=$(smart_field 'media_errors')
  fi
  if [ -n "${BAT:-}" ] && [ -r "$BAT/capacity" ]; then
    bpct=$(cat "$BAT/capacity" 2>/dev/null)
  fi
  # Sanitize: strip "+", and coerce non-numeric values to null so
  # the output is always valid JSON (no `+47.8`, no empty strings).
  num() {
    local v=${1:-}
    v=${v#+}
    case "$v" in ''|*[!0-9]*) printf 'null' ;; *) printf '%s' "$v" ;; esac
  }
  # temps can be decimals; allow one dot
  dec() {
    local v=${1:-}
    v=${v#+}
    case "$v" in ''|*[!0-9.]*|*.*.*) printf 'null' ;; *) printf '%s' "$v" ;; esac
  }
  printf '{"cpu_temp":%s,"gpu_temp":%s,"mem_avail_mb":%s,"swap_total_mb":%s,"ssd_life_pct":%s,"ssd_media_errors":%s,"battery_pct":%s,"cores":%s}\n' \
    "$(dec "$c")" "$(dec "$g")" "$(num "$a")" "$(num "$st")" \
    "$(num "$life")" "$(num "$media")" "$(num "$bpct")" "$CORES"
  exit 0
fi

if [ "$BRIEF" = "1" ]; then
  c=$(read_cpu_temp); a=$(free -m | awk '/^Mem:/{print $7}')
  life=$( [ -n "$SMART" ] && echo $(( 100 - $(smart_field 'percentage_used') )) || echo "?" )
  printf 'CPU %s°C | RAM %s MB free | SSD %s%% life | ' "${c:--}" "${a:--}" "${life}"
  systemctl is-active zram-swap earlyoom 2>/dev/null | tr '\n' ' '
  printf '%s' "$(systemctl --user is-active noc-monitor 2>/dev/null)"
  printf '\n'
  exit 0
fi

printf '%sLAPTOP HEALTH REPORT%s  %s  %s\n' "$B" "$R" "$(hostname)" "$(date '+%F %T')"
rule
check_temp
check_ram
check_ssd
check_battery
check_services
check_errors

section "VERDICT"
if [ "$CRIT" -gt 0 ]; then
  printf '  %s%sCRITICAL%s — %d critical, %d warning(s)\n' "$Rd" "$B" "$R" "$CRIT" "$WARN"
  printf '  Action needed. Back up important data.\n'
  rule; exit 2
elif [ "$WARN" -gt 0 ]; then
  printf '  %s%sGOOD WITH NOTES%s — %d warning(s), no criticals\n' "$Y" "$B" "$R" "$WARN"
  printf '  Safe to keep using. Review the items marked !\n'
  rule; exit 1
else
  printf '  %s%sALL HEALTHY%s — 0 warnings, 0 criticals\n' "$G" "$B" "$R"
  printf '  Nothing to do.\n'
  rule; exit 0
fi
