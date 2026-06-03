#!/usr/bin/env bash
# disk-audit.sh — Disk usage analysis + remediation advisor
# Usage: sudo bash disk-audit.sh [--top N] [--threshold GB]
# Env:   PROMETHEUS_DATA=/path  (override default /var/lib/prometheus)

# No set -euo pipefail — benign failures (missing dirs, empty globs) must not abort the script

# ── Config ───────────────────────────────────────────────────────────────────
TOP_N=20
LARGE_FILE_GB=1
PROMETHEUS_DATA="${PROMETHEUS_DATA:-/var/lib/prometheus}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --top)       TOP_N="$2";          shift 2 ;;
    --threshold) LARGE_FILE_GB="$2";  shift 2 ;;
    *)           shift ;;
  esac
done

DIR_WARN_MB=200
DIR_HIGH_MB=500

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Recommendation accumulator ───────────────────────────────────────────────
# Use $'\x01' as field separator — guaranteed not in titles/commands
SEP=$'\x01'
REC_PRIORITIES=()
REC_TITLES=()
REC_EXPLANATIONS=()
REC_COMMANDS=()

add_rec() {
  # add_rec PRIORITY "title" "explanation" "commands"
  REC_PRIORITIES+=("$1")
  REC_TITLES+=("$2")
  REC_EXPLANATIONS+=("$3")
  REC_COMMANDS+=("$4")
}

# ── Helpers ──────────────────────────────────────────────────────────────────
section()  { echo -e "\n${BOLD}${CYAN}━━━  $1  ━━━${RESET}"; }
finding()  { echo -e "  ${YELLOW}▶${RESET} $1"; }
ok()       { echo -e "  ${GREEN}✓${RESET} $1"; }
note()     { echo -e "  ${MAGENTA}ℹ${RESET} $1"; }

require_root() {
  [[ $EUID -eq 0 ]] || { echo -e "${RED}Run as root (sudo).${RESET}"; exit 1; }
}

# Returns size in MB as integer (0 if path missing)
size_mb() {
  local path="$1"
  [[ -e "$path" ]] || { echo 0; return; }
  du -sm "$path" 2>/dev/null | awk '{print int($1)}'
}

# Colorised human size
hsize() {
  local mb="$1"
  local human
  if command -v numfmt &>/dev/null; then
    human=$(numfmt --to=iec --suffix=B $((mb * 1024 * 1024)) 2>/dev/null)
  else
    human="${mb}M"
  fi
  if   (( mb >= 2000 )); then echo -e "${RED}${human}${RESET}"
  elif (( mb >= 500  )); then echo -e "${YELLOW}${human}${RESET}"
  else                        echo -e "${GREEN}${human}${RESET}"
  fi
}

# Print top N subdirs of a path
drill() {
  local dir="$1" depth="${2:-2}"
  [[ -d "$dir" ]] || return 0
  du -h --max-depth="$depth" "$dir" 2>/dev/null \
    | grep -v "^0\s" | sort -rh | head -n "$TOP_N" \
    | awk '{printf "    %-12s %s\n", $1, $2}'
}

# ── Start ────────────────────────────────────────────────────────────────────
require_root
echo -e "${BOLD}Disk Audit — $(hostname) — $(date '+%Y-%m-%d %H:%M:%S')${RESET}"

# ── 1. Filesystem Overview ───────────────────────────────────────────────────
section "Filesystem Overview"
df -h --output=source,fstype,size,used,avail,pcent,target \
  | grep -Ev "^(Filesystem|tmpfs|udev|devtmpfs)"

while IFS= read -r line; do
  pct=$(echo "$line" | awk '{print $1}' | tr -d '%')
  mnt=$(echo "$line" | awk '{print $2}')
  if [[ "$pct" =~ ^[0-9]+$ ]] && (( pct >= 80 )); then
    finding "${mnt} is at ${pct}% — attention needed"
    add_rec "HIGH" \
      "Filesystem ${mnt} at ${pct}% full" \
      "At 95%+ writes start failing silently. Address the top consumers identified below." \
      "# Track progress after each fix:\n  df -h ${mnt}"
  fi
done < <(df --output=pcent,target 2>/dev/null | tail -n +2 | grep -Ev "tmpfs|udev|devtmpfs")

# ── 2. Top-Level Breakdown ───────────────────────────────────────────────────
section "Top-Level Directory Sizes ( / )"
du -h --max-depth=1 / 2>/dev/null \
  | grep -v "^0" | sort -rh | head -n "$TOP_N" \
  | awk '{printf "  %-12s %s\n", $1, $2}'

# ── 3. /var ──────────────────────────────────────────────────────────────────
VAR_MB=$(size_mb /var)
if (( VAR_MB >= DIR_WARN_MB )); then
  section "/var  [$(hsize "$VAR_MB")]  — drilling in"
  drill /var 2

  # /var/log ──────────────────────────────────────────────────────────────────
  LOG_MB=$(size_mb /var/log)
  if (( LOG_MB >= DIR_WARN_MB )); then
    finding "/var/log is $(hsize "$LOG_MB")"
    drill /var/log 2

    JOURNAL_MB=$(size_mb /var/log/journal)
    if (( JOURNAL_MB >= 100 )); then
      finding "systemd journal: $(hsize "$JOURNAL_MB")"
      add_rec "HIGH" \
        "/var/log/journal is ${JOURNAL_MB}MB" \
        "Journals accumulate indefinitely without a size cap. Vacuum to 7 days and make the cap permanent." \
        "# One-time vacuum:\n  journalctl --vacuum-time=7d\n  journalctl --vacuum-size=200M\n\n# Make permanent:\n  mkdir -p /etc/systemd/journald.conf.d\n  printf '[Journal]\nSystemMaxUse=200M\nMaxRetentionSec=7day\n' > /etc/systemd/journald.conf.d/size.conf\n  systemctl restart systemd-journald"
    fi

    ROTATED_MB=$(find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.2" -o -name "*.old" -o -name "*.bak" \) \
      -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {printf "%d", s/1024/1024+0}')
    if (( ROTATED_MB >= 50 )); then
      finding "Rotated/compressed logs: ~${ROTATED_MB}MB"
      find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.2" -o -name "*.old" -o -name "*.bak" \) \
        -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -10 \
        | awk '{printf "    %6.1f MB  %s\n", $1/1024/1024, $2}'
      add_rec "MEDIUM" \
        "Rotated logs consuming ~${ROTATED_MB}MB in /var/log" \
        "Compressed .gz and numbered rotated logs are safe to delete once you've confirmed no active incidents need them." \
        "# Preview:\n  find /var/log -type f \\( -name '*.gz' -o -name '*.1' -o -name '*.2' -o -name '*.old' -o -name '*.bak' \\) -ls\n\n# Delete:\n  find /var/log -type f \\( -name '*.gz' -o -name '*.1' -o -name '*.2' -o -name '*.old' -o -name '*.bak' \\) -delete\n\n# Truncate any currently large active logs (doesn't break the service):\n  truncate -s 0 /var/log/syslog\n  truncate -s 0 /var/log/auth.log"
    fi
  else
    ok "/var/log is $(hsize "$LOG_MB")"
  fi

  # APT cache ─────────────────────────────────────────────────────────────────
  APT_MB=$(size_mb /var/cache/apt/archives)
  if (( APT_MB >= 50 )); then
    finding "APT package cache: $(hsize "$APT_MB")"
    add_rec "MEDIUM" \
      "APT cache is ${APT_MB}MB" \
      "Downloaded .deb files kept after installation. Entirely safe to delete." \
      "apt-get clean\n# Remove outdated packages only (keeps current cached versions):\n  apt-get autoclean\n# Remove orphaned dependency packages:\n  apt-get autoremove --purge"
  else
    ok "APT cache: $(hsize "$APT_MB")"
  fi

  # APT lists ─────────────────────────────────────────────────────────────────
  APTLIST_MB=$(size_mb /var/lib/apt/lists)
  if (( APTLIST_MB >= 200 )); then
    finding "/var/lib/apt/lists: $(hsize "$APTLIST_MB")"
    add_rec "LOW" \
      "APT package lists are ${APTLIST_MB}MB" \
      "The package index is regenerated by apt-get update. Safe to delete for emergency space." \
      "rm -rf /var/lib/apt/lists/*\napt-get update"
  fi

  # Prometheus TSDB ───────────────────────────────────────────────────────────
  PROM_MB=$(size_mb "$PROMETHEUS_DATA")
  if (( PROM_MB >= DIR_WARN_MB )); then
    finding "Prometheus TSDB: $(hsize "$PROM_MB") at ${PROMETHEUS_DATA}"
    echo ""
    echo "  TSDB blocks (oldest → newest):"
    while IFS= read -r block; do
      sz=$(du -sh "$block" 2>/dev/null | awk '{print $1}')
      nm=$(basename "$block")
      if [[ -f "$block/meta.json" ]]; then
        min_t=$(python3 -c "
import json,datetime
d=json.load(open('$block/meta.json'))
t=d.get('minTime',0)//1000
print(datetime.datetime.utcfromtimestamp(t).strftime('%Y-%m-%d'))
" 2>/dev/null || echo "?")
        max_t=$(python3 -c "
import json,datetime
d=json.load(open('$block/meta.json'))
t=d.get('maxTime',0)//1000
print(datetime.datetime.utcfromtimestamp(t).strftime('%Y-%m-%d'))
" 2>/dev/null || echo "?")
        printf "    %-28s %6s   [%s → %s]\n" "$nm" "$sz" "$min_t" "$max_t"
      else
        printf "    %-28s %6s\n" "$nm" "$sz"
      fi
    done < <(find "$PROMETHEUS_DATA" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)

    WAL_MB=$(size_mb "${PROMETHEUS_DATA}/wal")
    echo ""
    note "WAL size: $(hsize "$WAL_MB")"
    if (( WAL_MB >= 512 )); then
      finding "WAL is large — may indicate compaction issues or high cardinality"
      add_rec "HIGH" \
        "Prometheus WAL is ${WAL_MB}MB" \
        "WAL > 512MB usually means Prometheus hasn't compacted recently, or active series count is very high. WAL is NOT subject to retention — it won't shrink until compaction runs." \
        "# Check if compaction is happening:\n  journalctl -u prometheus --since '1 hour ago' | grep -i compact\n\n# Check active series count:\n  curl -s localhost:9090/api/v1/status/tsdb | python3 -m json.tool | grep numSeries\n\n# Restart Prometheus to trigger compaction:\n  systemctl restart prometheus"
    fi

    echo ""
    note "Current retention config:"
    systemctl cat prometheus 2>/dev/null | grep -E "storage\.(tsdb|remote)" \
      || grep -r "storage.tsdb" /etc/prometheus/ /etc/default/prometheus 2>/dev/null \
      || echo "    (could not auto-detect — check your unit file)"

    add_rec "MEDIUM" \
      "Prometheus TSDB is ${PROM_MB}MB — review retention settings" \
      "Without --storage.tsdb.retention.size set, disk fills unbounded. Best practice: set both a time AND a size limit." \
      "# Check current retention flags:\n  systemctl cat prometheus | grep storage\n\n# Edit the unit to add retention limits:\n  systemctl edit prometheus\n  # Add under [Service] -> ExecStart:\n  #   --storage.tsdb.retention.time=30d\n  #   --storage.tsdb.retention.size=4GB\n\n  systemctl daemon-reload && systemctl restart prometheus\n\n# Emergency: reclaim space now by removing old TSDB blocks\n# (data loss — Prometheus will re-scrape going forward)\n  systemctl stop prometheus\n  find ${PROMETHEUS_DATA} -maxdepth 1 -mindepth 1 -type d -not -name 'wal' -not -name 'chunks_head' | sort | head -n -2 | xargs rm -rf\n  systemctl start prometheus"
  else
    ok "Prometheus TSDB: $(hsize "$PROM_MB")"
  fi

  # Docker / Podman ───────────────────────────────────────────────────────────
  DOCKER_MB=$(size_mb /var/lib/docker)
  if (( DOCKER_MB >= DIR_WARN_MB )); then
    finding "/var/lib/docker: $(hsize "$DOCKER_MB")"
    add_rec "MEDIUM" \
      "/var/lib/docker is ${DOCKER_MB}MB" \
      "Docker accumulates stopped containers, dangling images, unused volumes, and build cache." \
      "# See breakdown:\n  docker system df\n\n# Safe prune (stopped containers, dangling images, unused networks):\n  docker system prune -f\n\n# Also remove unused volumes (careful — deletes data in unnamed volumes):\n  docker system prune -f --volumes\n\n# Remove ALL unused images including tagged:\n  docker image prune -a -f"
  fi

  PODMAN_MB=$(size_mb /var/lib/containers)
  if (( PODMAN_MB >= DIR_WARN_MB )); then
    finding "/var/lib/containers (Podman): $(hsize "$PODMAN_MB")"
    add_rec "MEDIUM" \
      "/var/lib/containers (Podman) is ${PODMAN_MB}MB" \
      "Podman accumulates stopped containers, dangling images, and unused volumes." \
      "# See breakdown:\n  podman system df\n\n# Prune unused containers, images, networks:\n  podman system prune -f\n\n# Also prune volumes:\n  podman system prune -f --volumes\n\n# Remove ALL unused images:\n  podman image prune -a -f"
  fi
else
  ok "/var is $(hsize "$VAR_MB")"
fi

# ── 4. /root ─────────────────────────────────────────────────────────────────
ROOT_MB=$(size_mb /root)
if (( ROOT_MB >= DIR_WARN_MB )); then
  section "/root  [$(hsize "$ROOT_MB")]  — drilling in"
  drill /root 2

  echo ""
  note "Largest files in /root:"
  find /root -type f -printf '%s\t%p\n' 2>/dev/null \
    | sort -rn | head -15 \
    | awk '{printf "    %7.1f MB  %s\n", $1/1024/1024, $2}'

  CORE_MB=$(find /root \( -name "core" -o -name "core.*" \) -type f -printf '%s\n' 2>/dev/null \
    | awk '{s+=$1} END {printf "%d", s/1024/1024+0}')
  if (( CORE_MB >= 50 )); then
    finding "Core dumps: ~${CORE_MB}MB"
    add_rec "MEDIUM" \
      "Core dumps in /root (~${CORE_MB}MB)" \
      "Core files from crashed processes. Safe to delete once investigated." \
      "# List them:\n  find /root \\( -name 'core' -o -name 'core.*' \\) -type f -ls\n\n# Delete:\n  find /root \\( -name 'core' -o -name 'core.*' \\) -type f -delete"
  fi

  PIP_MB=$(size_mb /root/.cache/pip)
  (( PIP_MB >= 50 )) && add_rec "LOW" \
    "pip cache in /root is ${PIP_MB}MB" \
    "pip wheel cache — safe to delete, rebuilds on next install." \
    "pip cache purge\n# Or directly:\n  rm -rf /root/.cache/pip"

  NPM_MB=$(size_mb /root/.npm)
  (( NPM_MB >= 50 )) && add_rec "LOW" \
    "npm cache in /root is ${NPM_MB}MB" \
    "npm download cache — safe to delete." \
    "npm cache clean --force\n# Or directly:\n  rm -rf /root/.npm"

  add_rec "MEDIUM" \
    "/root home directory is ${ROOT_MB}MB" \
    "/root should only contain dotfiles and small configs. Large files here are usually forgotten downloads, tarballs, or build artefacts." \
    "# Find largest files:\n  find /root -type f -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -20 | awk '{printf \"%7.1f MB  %s\n\", \$1/1024/1024, \$2}'\n\n# Common culprits:\n  ls -lh /root/*.tar.gz /root/*.deb /root/*.iso /root/go /root/.local 2>/dev/null || true\n\n# Find dirs > 50MB:\n  du -h --max-depth=3 /root 2>/dev/null | sort -rh | head -20"
fi

# ── 5. /home ─────────────────────────────────────────────────────────────────
HOME_MB=$(size_mb /home)
if (( HOME_MB >= DIR_WARN_MB )); then
  section "/home  [$(hsize "$HOME_MB")]  — per-user breakdown"
  drill /home 1
  for userdir in /home/*/; do
    [[ -d "$userdir" ]] || continue
    u_mb=$(size_mb "$userdir")
    if (( u_mb >= DIR_WARN_MB )); then
      finding "$userdir: $(hsize "$u_mb")"
      drill "$userdir" 1
      uname=$(basename "$userdir")
      add_rec "MEDIUM" \
        "${uname} home is ${u_mb}MB" \
        "Check for downloads, build artefacts, and tool caches." \
        "# Largest files:\n  find ${userdir} -type f -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -20 | awk '{printf \"%7.1f MB  %s\n\", \$1/1024/1024, \$2}'\n\n# Common caches:\n  rm -rf ${userdir}.cache/pip ${userdir}.npm ${userdir}.cache/go ${userdir}.cargo/registry"
    fi
  done
fi

# ── 6. /tmp ──────────────────────────────────────────────────────────────────
TMP_MB=$(size_mb /tmp)
if (( TMP_MB >= DIR_WARN_MB )); then
  section "/tmp  [$(hsize "$TMP_MB")]"
  find /tmp -type f -printf '%s\t%p\n' 2>/dev/null \
    | sort -rn | head -15 \
    | awk '{printf "    %7.1f MB  %s\n", $1/1024/1024, $2}'
  add_rec "MEDIUM" \
    "/tmp is ${TMP_MB}MB" \
    "Large files in /tmp are usually abandoned job outputs or extracted archives." \
    "# Files older than 7 days (safe to delete):\n  find /tmp -type f -atime +7 -ls\n  find /tmp -type f -atime +7 -delete\n\n# Check which processes have files open in /tmp (don't delete those):\n  lsof +D /tmp 2>/dev/null | awk 'NR>1 {print \$1, \$9}' | sort -u"
fi

# ── 7. /usr — old kernels ─────────────────────────────────────────────────────
USR_MB=$(size_mb /usr)
if (( USR_MB >= 2000 )); then
  section "/usr  [$(hsize "$USR_MB")]"
  KERNEL_COUNT=$(ls /boot/vmlinuz-* 2>/dev/null | wc -l)
  RUNNING_KERNEL=$(uname -r)
  note "Running kernel: $RUNNING_KERNEL"
  note "Installed kernels: $KERNEL_COUNT"
  if (( KERNEL_COUNT >= 3 )); then
    finding "${KERNEL_COUNT} kernel versions installed"
    ls /boot/vmlinuz-* 2>/dev/null | sed 's|/boot/vmlinuz-||' | awk '{print "    "$0}'
    add_rec "LOW" \
      "${KERNEL_COUNT} old kernel versions installed" \
      "Each old kernel keeps headers, modules, and initramfs (~300-600MB each). autoremove handles this safely." \
      "# Preview what would be removed:\n  apt-get --dry-run autoremove\n\n# Remove:\n  apt-get autoremove --purge"
  fi
fi

# ── 8. systemd core dumps ─────────────────────────────────────────────────────
COREDUMP_MB=$(size_mb /var/lib/systemd/coredump)
if (( COREDUMP_MB >= 50 )); then
  section "systemd Core Dumps  [$(hsize "$COREDUMP_MB")]"
  coredumpctl list 2>/dev/null | tail -n 10 || ls -lh /var/lib/systemd/coredump/ 2>/dev/null || true
  add_rec "MEDIUM" \
    "systemd core dumps: ${COREDUMP_MB}MB" \
    "Core dumps pile up after process crashes. Review them if debugging, then clean up." \
    "# List with context:\n  coredumpctl list\n\n# Remove all:\n  coredumpctl clean\n# Or directly:\n  rm -f /var/lib/systemd/coredump/*\n\n# Cap future storage:\n  echo 'Storage=none' >> /etc/systemd/coredump.conf\n  systemctl daemon-reload"
fi

# ── 9. Large files system-wide ───────────────────────────────────────────────
section "Large Files System-Wide  (≥ ${LARGE_FILE_GB}GB)"
echo "  Scanning..."
LARGE_RESULTS=$(find / -xdev \
  -not \( -path "/proc/*" -o -path "/sys/*" -o -path "/dev/*" \) \
  -type f -size +"${LARGE_FILE_GB}G" \
  -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -n "$TOP_N")

if [[ -n "$LARGE_RESULTS" ]]; then
  echo "$LARGE_RESULTS" | awk '{printf "  %7.2f GB  %s\n", $1/1024/1024/1024, $2}'
else
  ok "No files >= ${LARGE_FILE_GB}GB found."
fi

# ── 10. Inode usage ──────────────────────────────────────────────────────────
section "Inode Usage"
note "High inode use can fill a filesystem even when bytes are free"
df -i | grep -Ev "^(Filesystem|tmpfs|udev|devtmpfs)"

while IFS= read -r line; do
  pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
  mnt=$(echo "$line" | awk '{print $6}')
  if [[ "$pct" =~ ^[0-9]+$ ]] && (( pct >= 70 )); then
    finding "Inode usage on $mnt: ${pct}%"
    add_rec "HIGH" \
      "Inode exhaustion risk on $mnt (${pct}% inodes used)" \
      "When inodes are exhausted no new files can be created even with free bytes. Caused by thousands of tiny files (logs, sessions, cache entries)." \
      "# Find top directories by inode count:\n  for d in /var /tmp /home /root /opt; do\n    echo \"\$(find \$d -xdev 2>/dev/null | wc -l) inodes  \$d\"\n  done | sort -rn\n\n# Common culprit — php session files:\n  find /var/lib/php -type f | wc -l\n  find /var/lib/php -type f -atime +1 -delete"
  fi
done < <(df -i 2>/dev/null | grep -Ev "^(Filesystem|tmpfs|udev|devtmpfs)")

# ── 11. Journal summary ───────────────────────────────────────────────────────
section "systemd Journal"
command -v journalctl &>/dev/null && journalctl --disk-usage || true

# ══════════════════════════════════════════════════════════════════════════════
# ── ACTION PLAN ──────────────────────────────────────────════════════════════
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}${MAGENTA}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${MAGENTA}║              ACTION PLAN                             ║${RESET}"
echo -e "${BOLD}${MAGENTA}╚══════════════════════════════════════════════════════╝${RESET}"

if [[ ${#REC_TITLES[@]} -eq 0 ]]; then
  ok "No significant issues found — disk usage looks healthy."
  echo ""
  echo -e "${BOLD}Done.${RESET}"
  exit 0
fi

echo -e "  ${RED}■ HIGH${RESET}   — address now, space at risk"
echo -e "  ${YELLOW}■ MEDIUM${RESET} — address soon, meaningful savings"
echo -e "  ${GREEN}■ LOW${RESET}   — housekeeping, minor gains"

for target_pri in HIGH MEDIUM LOW; do
  printed_header=0
  for i in "${!REC_TITLES[@]}"; do
    [[ "${REC_PRIORITIES[$i]}" != "$target_pri" ]] && continue

    if [[ $printed_header -eq 0 ]]; then
      echo ""
      case "$target_pri" in
        HIGH)   echo -e "  ${RED}${BOLD}── HIGH ───────────────────────────────────────────${RESET}" ;;
        MEDIUM) echo -e "  ${YELLOW}${BOLD}── MEDIUM ─────────────────────────────────────────${RESET}" ;;
        LOW)    echo -e "  ${GREEN}${BOLD}── LOW ────────────────────────────────────────────${RESET}" ;;
      esac
      printed_header=1
    fi

    echo ""
    case "$target_pri" in
      HIGH)   echo -e "  ${RED}▶${RESET} ${BOLD}${REC_TITLES[$i]}${RESET}" ;;
      MEDIUM) echo -e "  ${YELLOW}▶${RESET} ${BOLD}${REC_TITLES[$i]}${RESET}" ;;
      LOW)    echo -e "  ${GREEN}▶${RESET} ${BOLD}${REC_TITLES[$i]}${RESET}" ;;
    esac
    echo "    ${REC_EXPLANATIONS[$i]}"
    echo ""
    echo -e "    ${BOLD}Commands:${RESET}"
    printf '%s\n' "${REC_COMMANDS[$i]}" | sed 's/^/    /'
  done
done

echo ""
echo -e "${BOLD}Done. Re-run this script after each fix to track progress.${RESET}"
