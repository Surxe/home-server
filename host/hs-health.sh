#!/usr/bin/env bash
# hs-health.sh — one-shot performance/health report for the home-server (Proxmox host).
#
# Read-only. Surfaces the things that actually go wrong on THIS box (headless old
# laptop, wifi uplink, LVM-thin storage, guests in VMs): load/CPU, memory+swap,
# temperature, filesystem + thin-pool fill, the wifi uplink + internet, guest VMs
# and their agent, and any failed systemd units. Each metric is graded OK/WARN/CRIT
# against a threshold; the script exits with the WORST grade seen (0/1/2), so it is
# equally usable by a human at the terminal and by a machine (see --line).
#
# Usage:
#   host/hs-health.sh            # full graded report (color when on a TTY)
#   host/hs-health.sh -q         # one-line summary only (for cron/alert bodies)
#   host/hs-health.sh --line     # single machine line "LEVEL | metrics — issues"
#                                 #   (this is what the Discord status notifier consumes)
#   host/hs-health.sh --no-guest # skip the in-guest agent probe (never blocks)
#   host/hs-health.sh --no-color
#
# Exit: 0 = all OK, 1 = at least one WARN, 2 = at least one CRIT (nagios-style).
#
# Privilege: qm and lvs need root. Run as root (sudo host/hs-health.sh) or as a user
# with passwordless sudo for those; when neither works those sections degrade to n/a
# rather than failing. Not "set -e": a health check deliberately runs commands that
# may fail, and one failing probe must not abort the whole report.
set -uo pipefail

# ---- thresholds (override via env) ------------------------------------------
: "${LOAD_WARN_PER_CORE:=1.0}" "${LOAD_CRIT_PER_CORE:=2.0}"  # load1 / nproc
: "${MEM_WARN:=90}"    "${MEM_CRIT:=95}"      # RAM used % (box baselines ~85%: VM holds 4G of 7G)
: "${SWAP_WARN:=50}"   "${SWAP_CRIT:=90}"     # swap used %
: "${TEMP_WARN:=75}"   "${TEMP_CRIT:=85}"     # °C
: "${FS_WARN:=85}"     "${FS_CRIT:=95}"       # filesystem used %
: "${THIN_WARN:=80}"   "${THIN_CRIT:=90}"     # LVM-thin data/meta used %
: "${SNAP_WARN:=8}"                            # VM snapshots piling up (thin space)
: "${PING_HOST:=1.1.1.1}"                      # internet reachability probe
: "${GUEST_TIMEOUT:=8}"                         # sec to wait on a guest agent

# ---- args -------------------------------------------------------------------
QUIET=0; DO_GUEST=1; COLOR=auto; MODE_LINE=0
for a in "$@"; do case "$a" in
  -q|--quiet)    QUIET=1 ;;
  --line)        MODE_LINE=1; QUIET=1; COLOR=off ;;   # one machine line, then exit
  --no-guest)    DO_GUEST=0 ;;
  --no-color)    COLOR=off ;;
  -h|--help)     awk 'NR>1 && /^#/{sub(/^# ?/,"");print} /^set /{exit}' "$0"; exit 0 ;;
  *) echo "unknown arg: $a (try -h)" >&2; exit 2 ;;
esac; done

# ---- presentation -----------------------------------------------------------
if [ "$COLOR" = auto ]; then [ -t 1 ] && COLOR=on || COLOR=off; fi
if [ "$COLOR" = on ]; then C_OK=$'\e[32m'; C_WARN=$'\e[33m'; C_CRIT=$'\e[31m'
  C_DIM=$'\e[2m'; C_BOLD=$'\e[1m'; C_0=$'\e[0m'
else C_OK=; C_WARN=; C_CRIT=; C_DIM=; C_BOLD=; C_0=; fi

WORST=0                      # 0 ok / 1 warn / 2 crit — tracks the whole run
declare -a NOTES=()         # WARN/CRIT one-liners, echoed in the summary
declare -a DIGEST=()        # compact "key val" tokens, joined for --line mode
bump() { [ "$1" -gt "$WORST" ] && WORST=$1; return 0; }
dg()   { DIGEST+=("$1"); return 0; }

# grade N.N against warn/crit -> 0/1/2  (float compare via awk)
grade() { awk -v v="$1" -v w="$2" -v c="$3" \
  'BEGIN{ if(v+0>=c)print 2; else if(v+0>=w)print 1; else print 0 }'; }

tag() { case "$1" in 0) printf '%s OK %s'  "$C_OK$C_BOLD"   "$C_0";;
                     1) printf '%sWARN%s'  "$C_WARN$C_BOLD" "$C_0";;
                     *) printf '%sCRIT%s'  "$C_CRIT$C_BOLD" "$C_0";; esac; }

# report LABEL GRADE DETAIL  — prints a graded line, records worst + any note
report() { local lbl="$1" g="$2" det="$3"
  bump "$g"
  [ "$QUIET" = 1 ] || printf '  [%s] %-11s %s\n' "$(tag "$g")" "$lbl" "$det"
  [ "$g" -ge 1 ] && NOTES+=("$(tag "$g") ${lbl}: ${det}")
  return 0; }
info() { [ "$QUIET" = 1 ] || printf '  %s· %-11s %s%s\n' "$C_DIM" "$1" "$2" "$C_0"; }
head_() { [ "$QUIET" = 1 ] || printf '\n%s%s%s\n' "$C_BOLD" "$1" "$C_0"; }

# privileged runner: direct as root, else sudo -n (never prompt in a monitor)
if [ "$(id -u)" -eq 0 ]; then priv() { "$@"; }; PRIV_OK=1
elif sudo -n true 2>/dev/null;   then priv() { sudo -n "$@"; }; PRIV_OK=1
else priv() { return 127; }; PRIV_OK=0; fi

NPROC="$(nproc 2>/dev/null || echo 1)"

[ "$QUIET" = 1 ] || printf '%shome-server health%s  %s  (%s)\n' \
  "$C_BOLD" "$C_0" "$(hostname)" "$(date '+%Y-%m-%d %H:%M:%S %Z')"

# ---- host -------------------------------------------------------------------
head_ "Host"
info uptime "$(uptime -p 2>/dev/null | sed 's/^up //')"
info kernel "$(uname -r)"
if command -v pveversion >/dev/null 2>&1; then info proxmox "$(pveversion 2>/dev/null)"; fi

# ---- CPU / load -------------------------------------------------------------
head_ "CPU / load"
read -r L1 L5 L15 _ < /proc/loadavg
g="$(grade "$(awk -v l="$L1" -v n="$NPROC" 'BEGIN{printf "%.3f", l/n}')" \
           "$LOAD_WARN_PER_CORE" "$LOAD_CRIT_PER_CORE")"
report load "$g" "$L1 $L5 $L15  (${NPROC} cores; 1-min = $(awk -v l="$L1" -v n="$NPROC" 'BEGIN{printf "%.0f%%", 100*l/n}') of cores)"
dg "load ${L1}/${NPROC}"
if command -v vmstat >/dev/null 2>&1; then
  IDLE="$(vmstat 1 2 2>/dev/null | tail -1 | awk '{print $15}')"
  [ -n "${IDLE:-}" ] && info cpu-busy "$((100 - IDLE))% (idle ${IDLE}%)"
fi

# ---- memory -----------------------------------------------------------------
head_ "Memory"
# used% from (total-available)/total; swap used% from used/total.
read -r MEMP SWAPP MEMH SWAPH < <(free -b | awk '
  /^Mem:/  {t=$2; a=$7; mu=(t? 100*(t-a)/t:0); mh=sprintf("%.1f/%.1fG", (t-a)/1073741824, t/1073741824)}
  /^Swap:/ {st=$2; su=$3; sp=(st? 100*su/st:0); sh=(st? sprintf("%.1f/%.1fG", su/1073741824, st/1073741824):"none")}
  END{printf "%.0f %.0f %s %s", mu, sp, mh, sh}')
report ram  "$(grade "$MEMP"  "$MEM_WARN"  "$MEM_CRIT")"  "${MEMP}% used  (${MEMH})"
report swap "$(grade "$SWAPP" "$SWAP_WARN" "$SWAP_CRIT")" "${SWAPP}% used  (${SWAPH})"
dg "ram ${MEMP}%"
[ "${SWAPP:-0}" -gt 0 ] 2>/dev/null && dg "swap ${SWAPP}%"

# ---- temperature ------------------------------------------------------------
head_ "Temperature"
any=0; maxt=-1
for z in /sys/class/thermal/thermal_zone*; do
  [ -r "$z/temp" ] || continue; any=1
  t="$(awk '{printf "%.0f", $1/1000}' "$z/temp" 2>/dev/null)"
  ty="$(cat "$z/type" 2>/dev/null || echo zone)"
  [ "${t:-0}" -gt "$maxt" ] 2>/dev/null && maxt=$t
  report "$ty" "$(grade "$t" "$TEMP_WARN" "$TEMP_CRIT")" "${t}°C"
done
[ "$any" = 0 ] && info temp "no thermal_zone sensors exposed (sensors pkg not installed)"
[ "$maxt" -ge 0 ] 2>/dev/null && dg "temp ${maxt}°C"

# ---- storage: filesystems ---------------------------------------------------
head_ "Storage — filesystems"
fsworst=0
while read -r use mnt src; do
  u="${use%\%}"
  [ "${u:-0}" -gt "$fsworst" ] 2>/dev/null && fsworst=$u
  report "$mnt" "$(grade "$u" "$FS_WARN" "$FS_CRIT")" "${use} used  ${C_DIM}(${src})${C_0}"
done < <(df -P -x tmpfs -x devtmpfs -x overlay -x efivarfs 2>/dev/null \
          | awk 'NR>1 && $1!="/dev/fuse" {print $5, $6, $1}')
dg "disk ${fsworst}%"

# ---- storage: LVM-thin pool -------------------------------------------------
head_ "Storage — LVM-thin"
if lvs_out="$(priv lvs --noheadings --separator '|' -o lv_name,lv_attr,data_percent,metadata_percent 2>/dev/null)"; then
  found=0
  while IFS='|' read -r name attr datap metap; do
    name="$(echo "$name" | xargs)"; attr="$(echo "$attr" | xargs)"
    # thin POOLS have attr starting with 't'
    [ "${attr:0:1}" = t ] || continue
    found=1
    dp="$(echo "$datap" | xargs)"; mp="$(echo "$metap" | xargs)"
    report "$name data" "$(grade "${dp:-0}" "$THIN_WARN" "$THIN_CRIT")" "${dp}% used"
    report "$name meta" "$(grade "${mp:-0}" "$THIN_WARN" "$THIN_CRIT")" "${mp}% used"
    dg "thin ${dp}%/${mp}%"
  done <<< "$lvs_out"
  # accumulated VM snapshots eat thin space silently — count them
  nsnap="$(priv lvs --noheadings -o lv_name 2>/dev/null | grep -c 'snap_')"
  if [ "${nsnap:-0}" -ge "$SNAP_WARN" ]; then
    report snapshots 1 "${nsnap} LVM snapshots (consuming thin pool; prune stale ones)"
  else
    info snapshots "${nsnap:-0} LVM snapshots"
  fi
  [ "$found" = 0 ] && info lvm-thin "no thin pool found"
else
  info lvm-thin "n/a (needs root/sudo)"
fi

# ---- network / uplink -------------------------------------------------------
head_ "Network — uplink"
if systemctl list-unit-files home-server-wifi.service >/dev/null 2>&1; then
  st="$(systemctl is-active home-server-wifi.service 2>/dev/null)"
  report wifi-svc "$([ "$st" = active ] && echo 0 || echo 2)" "home-server-wifi.service = ${st:-unknown}"
fi
# wireless iface = the one with a wireless dir under /sys/class/net
wif=""; for n in /sys/class/net/*/wireless; do wif="$(basename "$(dirname "$n")")"; break; done
if [ -n "$wif" ]; then
  oper="$(cat "/sys/class/net/$wif/operstate" 2>/dev/null)"
  ip4="$(ip -4 -o addr show "$wif" 2>/dev/null | awk '{print $4}' | head -1)"
  report "link ($wif)" "$([ "$oper" = up ] && echo 0 || echo 2)" "operstate=$oper  ${ip4:-no-ipv4}"
fi
if ping -c1 -W2 "$PING_HOST" >/dev/null 2>&1; then
  report internet 0 "reachable ($PING_HOST)"; dg "net up"
else
  report internet 2 "cannot reach $PING_HOST"; dg "net DOWN"
fi

# ---- guest VMs --------------------------------------------------------------
head_ "Guest VMs"
if qm_out="$(priv qm list 2>/dev/null)"; then
  vmrun=0; vmtot=0
  while read -r vmid name status _; do
    [ "$vmid" = VMID ] && continue
    [ -z "${vmid:-}" ] && continue
    vmtot=$((vmtot+1)); [ "$status" = running ] && vmrun=$((vmrun+1))
    if [ "$status" = running ]; then
      det="running"
      if [ "$DO_GUEST" = 1 ]; then
        if timeout "$GUEST_TIMEOUT" bash -c "$(declare -f priv); priv qm guest exec $vmid -- /bin/true" >/dev/null 2>&1; then
          det="running, agent responsive"
        else
          report "VM $vmid ($name)" 1 "running, GUEST AGENT NOT RESPONDING (timeout ${GUEST_TIMEOUT}s)"; continue
        fi
      fi
      report "VM $vmid ($name)" 0 "$det"
    else
      report "VM $vmid ($name)" 1 "status=$status"
    fi
  done <<< "$qm_out"
  dg "VMs ${vmrun}/${vmtot}"
else
  info qm "n/a (needs root/sudo)"
fi

# ---- systemd services -------------------------------------------------------
head_ "Services"
failed="$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | paste -sd, -)"
if [ -n "$failed" ]; then report systemd 2 "failed units: $failed"; nfail="$(printf '%s' "$failed" | tr ',' '\n' | grep -c .)"
else report systemd 0 "no failed units"; nfail=0; fi
dg "${nfail} failed"
# how many of this box's own timers are active (informational)
ht="$(systemctl list-timers 'hs-*' --no-legend 2>/dev/null | grep -c .)"
info hs-timers "${ht:-0} home-server timers scheduled"

# ---- machine line (--line) --------------------------------------------------
# One line the Discord notifier (and any alert) can consume: "LEVEL | metrics — issues".
if [ "$MODE_LINE" = 1 ]; then
  lvl=OK; [ "$WORST" -ge 1 ] && lvl=WARN; [ "$WORST" -ge 2 ] && lvl=CRIT
  d=""; for p in "${DIGEST[@]}"; do d="${d:+$d · }$p"; done
  line="$lvl | $d"
  if [ "${#NOTES[@]}" -gt 0 ]; then
    n=""; for x in "${NOTES[@]}"; do n="${n:+$n; }$x"; done
    line="$line — $n"
  fi
  printf '%s\n' "$line"
  exit "$WORST"
fi

# ---- summary ----------------------------------------------------------------
SUMTAG="$(tag "$WORST")"
if [ "$QUIET" = 1 ]; then
  if [ "$WORST" = 0 ]; then printf '[%s] home-server: all checks passed\n' "$SUMTAG"
  else printf '[%s] home-server: %s\n' "$SUMTAG" "$(IFS='; '; echo "${NOTES[*]}")"; fi
else
  head_ "Summary"
  if [ "$WORST" = 0 ]; then printf '  [%s] all checks passed\n' "$SUMTAG"
  else printf '  [%s] %d issue(s):\n' "$SUMTAG" "${#NOTES[@]}"
       for n in "${NOTES[@]}"; do printf '      - %s\n' "$n"; done; fi
  [ "$PRIV_OK" = 0 ] && printf '  %s(run with sudo for LVM-thin + VM checks)%s\n' "$C_DIM" "$C_0"
fi
exit "$WORST"
