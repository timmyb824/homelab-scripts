#!/usr/bin/env bash
# disk-audit.sh — Disk usage analysis + remediation advisor
# Usage: sudo bash disk-audit.sh [--top N] [--threshold GB]
# Env:   PROMETHEUS_DATA=/path  (override default /var/lib/prometheus)

set -euo pipefail

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

# Thresholds for "interesting" directories (in MB)
DIR_WARN_MB=200
DIR_HIGH_MB=500

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Recommendation accumulator ───────────────────────────────────────────────
# Format: "PRIORITY|||TITLE|||EXPLANATION|||COMMANDS"
RECS=()

add_rec() {
  # add_rec HIGH "title" "why this matters" "cmd1\ncmd2\ncmd3"
  RECS+=("$1|||$2|||$3|||$4")
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

# Human-readable with colour based on size
hsize() {
  local mb="$1"
  local human
  human=$(numfmt --to=iec --suffix=B $((mb * 1024 * 1024)) 2>/dev/null || echo "${mb}M")
  if   (( mb >= 2000 )); then echo -e "${RED}${human}${RESET}"
  elif (( mb >= 500  )); then echo -e "${YELLOW}${human}${RESET}"
  else                        echo -e "${GREEN}${human}${RESET}"
  fi
}

# Drill into a directory, show top N subdirs
drill() {
  local dir="$1"
  local depth="${2:-2}"
  [[ -d "$dir" ]] || return
  du -h --max-depth="$depth" "$dir" 2>/dev/null \
    | grep -v "^0\s" \
    | sort -rh \
    | head -n "$TOP_N" \
    | awk '{printf "    %-12s %s\n", $1, $2}'
}

# ── Start ────────────────────────────────────────────────────────────────────
require_root
echo -e "${BOLD}Disk Audit — $(hostname) — $(date '+%Y-%m-%d %H:%M:%S')${RESET}"

# ── 1. Overall Filesystem Usage ──────────────────────────────────────────────
section "Filesystem Overview"
df -h --output=source,fstype,size,used,avail,pcent,target \
  | grep -Ev "^(Filesystem|tmpfs|udev|devtmpfs)"

# Flag disks ≥ 80%
while IFS= read -r line; do
  pct=$(echo "$line" | awk '{print $6}' | tr -d '%')
  mnt=$(echo "$line" | awk '{print $7}')
  if [[ "$pct" =~ ^[0-9]+$ ]] && (( pct >= 80 )); then
    finding "$(printf '%s is at %s%% — attention needed' "$mnt" "$pct")"
    add_rec "HIGH" \
      "Filesystem $mnt at ${pct}%" \
      "You're at ${pct}% on $mnt. At 95%+ writes start failing silently. Address the top consumers below first." \
      "# Re-run this script after each fix to track progress:\n  df -h $mnt"
  fi
done < <(df --output=pcent,target 2>/dev/null | tail -n +2 | grep -Ev "tmpfs|udev|devtmpfs")

# ── 2. Top-Level Breakdown ───────────────────────────────────────────────────
section "Top-Level Directory Sizes ( / )"
du -h --max-depth=1 / 2>/dev/null \
  | grep -v "^0" \
  | sort -rh \
  | head -n "$TOP_N" \
  | awk '{printf "  %-12s %s\n", $1, $2}'

# ── 3. /var Analysis ─────────────────────────────────────────────────────────
VAR_MB=$(size_mb /var)
if (( VAR_MB >= DIR_WARN_MB )); then
  section "/var Breakdown  [$(hsize "$VAR_MB")]  — drilling in"
  drill /var 2

  # /var/log
  LOG_MB=$(size_mb /var/log)
  if (( LOG_MB >= DIR_WARN_MB )); then
    finding "/var/log is $(hsize "$LOG_MB") — checking contents"
    drill /var/log 2

    # Journal
    JOURNAL_MB=$(size_mb /var/log/journal)
    if (( JOURNAL_MB >= 100 )); then
      finding "systemd journal: $(hsize "$JOURNAL_MB")"
      add_rec "HIGH" \
        "/var/log/journal is ${JOURNAL_MB}MB" \
        "systemd journals accumulate indefinitely unless capped. Vacuum to 7 days and cap future growth." \
        "# One-time vacuum:\n  journalctl --vacuum-time=7d\n  journalctl --vacuum-size=200M\n\n# Make the size cap permanent:\n  mkdir -p /etc/systemd/journald.conf.d\n  echo -e '[Journal]\nSystemMaxUse=200M\nMaxRetentionSec=7day' > /etc/systemd/journald.conf.d/size.conf\n  systemctl restart systemd-journald"
    fi

    # Rotated / compressed logs
    ROTATED_MB=$(find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.2" -o -name "*.old" -o -name "*.bak" \) \
      -printf '%s\n' 2>/dev/null | awk '{s+=$1} END {printf "%d", s/1024/1024}')
    if (( ROTATED_MB >= 50 )); then
      finding "Rotated/compressed logs: ~${ROTATED_MB}MB"
      echo "    Top rotated files:"
      find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.2" -o -name "*.old" -o -name "*.bak" \) \
        -printf '%s\t%p\n' 2>/dev/null \
        | sort -rn | head -n 10 \
        | awk '{printf "    %6.1f MB  %s\n", $1/1024/1024, $2}'
      add_rec "MEDIUM" \
        "Rotated logs consuming ~${ROTATED_MB}MB in /var/log" \
        "Compressed .gz and numbered rotated logs can be safely deleted once you've confirmed no active incidents need them." \
        "# Preview what would be removed:\n  find /var/log -type f \\( -name '*.gz' -o -name '*.1' -o -name '*.2' -o -name '*.old' -o -name '*.bak' \\) -ls\n\n# Delete them:\n  find /var/log -type f \\( -name '*.gz' -o -name '*.1' -o -name '*.2' -o -name '*.old' -o -name '*.bak' \\) -delete\n\n# Optionally truncate any actively-growing logs that are large:\n  truncate -s 0 /var/log/syslog\n  truncate -s 0 /var/log/auth.log"
    fi
  else
    ok "/var/log is $(hsize "$LOG_MB") — looks fine"
  fi

  # /var/cache/apt
  APT_MB=$(size_mb /var/cache/apt/archives)
  if (( APT_MB >= 50 )); then
    finding "APT package cache: $(hsize "$APT_MB")"
    add_rec "MEDIUM" \
      "APT cache is ${APT_MB}MB" \
      "Downloaded .deb files are kept after installation. Safe to delete entirely." \
      "apt-get clean\n# Or to only remove outdated packages (keeps current cached versions):\n  apt-get autoclean\n# Also remove orphaned dependency packages:\n  apt-get autoremove --purge"
  else
    ok "APT cache: $(hsize "$APT_MB") — fine"
  fi

  # /var/lib/prometheus
  PROM_MB=$(size_mb "$PROMETHEUS_DATA")
  if (( PROM_MB >= DIR_WARN_MB )); then
    finding "Prometheus TSDB: $(hsize "$PROM_MB")"

    echo "  TSDB blocks (oldest → newest):"
    find "$PROMETHEUS_DATA" -maxdepth 1 -mindepth 1 -type d 2>/dev/null \
      | sort \
      | while read -r block; do
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
        done

    # WAL
    WAL_MB=$(size_mb "${PROMETHEUS_DATA}/wal")
    if (( WAL_MB >= 512 )); then
      finding "WAL is large: $(hsize "$WAL_MB") — may indicate compaction issues or high cardinality"
      add_rec "HIGH" \
        "Prometheus WAL is ${WAL_MB}MB" \
        "A large WAL (>512MB) usually means either: (a) Prometheus hasn't compacted recently — check if it's running and healthy, or (b) very high active series count. WAL data is NOT subject to retention and won't shrink until compaction runs." \
        "# Check if Prometheus is compacting (should see TSDB compaction log entries):\n  journalctl -u prometheus --since '1 hour ago' | grep -i compact\n\n# Check active series count via API:\n  curl -s localhost:9090/api/v1/status/tsdb | python3 -m json.tool | grep numSeries\n\n# If Prometheus is stuck, a clean restart triggers compaction:\n  systemctl restart prometheus\n\n# Check cardinality (top 10 metrics by series count):\n  curl -s 'localhost:9090/api/v1/label/__name__/values' | python3 -c \"\nimport json,sys\nd=json.load(sys.stdin)\nprint('\\n'.join(sorted(d['data'])[:20]))\""
    fi

    # Retention config
    echo ""
    note "Current Prometheus retention config:"
    systemctl cat prometheus 2>/dev/null | grep -E "storage\.(tsdb|remote)" || \
      grep -r "storage.tsdb" /etc/prometheus/ /etc/default/prometheus 2>/dev/null || \
      echo "    (could not auto-detect — check your unit file or /etc/default/prometheus)"

    add_rec "MEDIUM" \
      "Prometheus TSDB is ${PROM_MB}MB — review retention settings" \
      "Prometheus keeps all data until the retention window expires. If you haven't set --storage.tsdb.retention.size, disk will fill unbounded. Best practice: set BOTH time and size limits." \
      "# Check current retention flags:\n  systemctl cat prometheus | grep storage\n\n# Edit the systemd unit (adjust values for your needs):\n  systemctl edit prometheus\n  # Add under [Service]:\n  #   ExecStart=... --storage.tsdb.retention.time=30d --storage.tsdb.retention.size=4GB\n\n# Apply:\n  systemctl daemon-reload && systemctl restart prometheus\n\n# If you need to reclaim space *now* (deletes all data — re-scrape will rebuild):\n  systemctl stop prometheus\n  rm -rf ${PROMETHEUS_DATA}/[0-9A-Z]*/   # removes old blocks only, not wal\n  systemctl start prometheus"
  else
    ok "Prometheus TSDB: $(hsize "$PROM_MB")"
  fi

  # /var/lib/docker or /var/lib/containers
  DOCKER_MB=$(size_mb /var/lib/docker)
  PODMAN_MB=$(size_mb /var/lib/containers)
  if (( DOCKER_MB >= DIR_WARN_MB )); then
    finding "/var/lib/docker: $(hsize "$DOCKER_MB")"
    add_rec "MEDIUM" \
      "/var/lib/docker is ${DOCKER_MB}MB" \
      "Docker accumulates stopped containers, dangling images, unused volumes, and build cache. 'system prune' is safe as long as you're not relying on stopped containers." \
      "# See a breakdown of what's using space:\n  docker system df\n\n# Remove stopped containers, dangling images, unused networks (safe):\n  docker system prune -f\n\n# Also remove unused volumes (careful — deletes data in unnamed volumes):\n  docker system prune -f --volumes\n\n# Remove all unused images (including tagged ones not tied to a container):\n  docker image prune -a -f"
  fi
  if (( PODMAN_MB >= DIR_WARN_MB )); then
    finding "/var/lib/containers: $(hsize "$PODMAN_MB")"
    add_rec "MEDIUM" \
      "/var/lib/containers (Podman) is ${PODMAN_MB}MB" \
      "Podman accumulates stopped containers, dangling images, and unused volumes similarly to Docker." \
      "# See breakdown:\n  podman system df\n\n# Prune unused containers, images, networks:\n  podman system prune -f\n\n# Also prune volumes:\n  podman system prune -f --volumes\n\n# Prune all unused images:\n  podman image prune -a -f"
  fi

  # /var/lib/apt
  APTLIB_MB=$(size_mb /var/lib/apt/lists)
  if (( APTLIB_MB >= 200 )); then
    finding "/var/lib/apt/lists: $(hsize "$APTLIB_MB")"
    add_rec "LOW" \
      "APT package lists are ${APTLIB_MB}MB" \
      "The package index can be regenerated with apt-get update at any time. Safe to delete if you need emergency space." \
      "# Remove and regenerate:\n  rm -rf /var/lib/apt/lists/*\n  apt-get update"
  fi
else
  ok "/var is $(hsize "$VAR_MB") — under threshold"
fi

# ── 4. /root Analysis ────────────────────────────────────────────────────────
ROOT_MB=$(size_mb /root)
if (( ROOT_MB >= DIR_WARN_MB )); then
  section "/root  [$(hsize "$ROOT_MB")]  — drilling in"
  drill /root 2

  # Core dumps
  CORE_MB=$(find /root -name "core" -o -name "core.*" -type f 2>/dev/null \
    | xargs du -sc 2>/dev/null | tail -1 | awk '{print int($1/1024)}')
  if (( CORE_MB >= 50 )); then
    finding "Core dumps found: ~${CORE_MB}MB"
    find /root -name "core" -o -name "core.*" 2>/dev/null | head -5 | awk '{print "    "$0}'
    add_rec "MEDIUM" \
      "Core dumps in /root (~${CORE_MB}MB)" \
      "Core files are generated when a process crashes. Safe to delete once you've investigated (or if you don't need them)." \
      "# List them:\n  find /root -name 'core' -o -name 'core.*' 2>/dev/null\n\n# Delete them:\n  find /root -name 'core' -o -name 'core.*' -delete"
  fi

  # pip cache
  PIP_MB=$(size_mb /root/.cache/pip)
  if (( PIP_MB >= 50 )); then
    finding "/root/.cache/pip: $(hsize "$PIP_MB")"
    add_rec "LOW" \
      "pip cache in /root is ${PIP_MB}MB" \
      "pip caches downloaded wheels to speed up reinstalls. Fully safe to delete — it will rebuild on next install." \
      "pip cache purge\n# Or directly:\n  rm -rf /root/.cache/pip"
  fi

  # npm cache
  NPM_MB=$(size_mb /root/.npm)
  if (( NPM_MB >= 50 )); then
    finding "/root/.npm cache: $(hsize "$NPM_MB")"
    add_rec "LOW" \
      "npm cache in /root is ${NPM_MB}MB" \
      "npm caches downloaded packages. Safe to delete." \
      "npm cache clean --force\n# Or directly:\n  rm -rf /root/.npm"
  fi

  # Large files in /root
  echo ""
  note "Largest files in /root:"
  find /root -type f -printf '%s\t%p\n' 2>/dev/null \
    | sort -rn | head -10 \
    | awk '{printf "    %7.1f MB  %s\n", $1/1024/1024, $2}'

  add_rec "MEDIUM" \
    "/root home directory is ${ROOT_MB}MB" \
    "/root should generally only contain dotfiles and small configs. Large files here are usually downloads, tarballs, or build artifacts that were never cleaned up." \
    "# Find the largest files in /root:\n  find /root -type f -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -20 | awk '{printf \"%7.1f MB  %s\n\", \$1/1024/1024, \$2}'\n\n# Find directories > 50MB:\n  du -h --max-depth=3 /root 2>/dev/null | sort -rh | head -20\n\n# Common culprits to check:\n  ls -lh /root/*.tar.gz /root/*.deb /root/*.iso /root/go /root/.local 2>/dev/null || true"
fi

# ── 5. /home Analysis ────────────────────────────────────────────────────────
HOME_MB=$(size_mb /home)
if (( HOME_MB >= DIR_WARN_MB )); then
  section "/home  [$(hsize "$HOME_MB")]  — per-user breakdown"
  drill /home 1
  for userdir in /home/*/; do
    u_mb=$(size_mb "$userdir")
    if (( u_mb >= DIR_WARN_MB )); then
      finding "$userdir: $(hsize "$u_mb") — notable subdirs:"
      drill "$userdir" 1
      add_rec "MEDIUM" \
        "$(basename "$userdir") home is ${u_mb}MB" \
        "Check for downloads, build artefacts, pip/npm/cargo caches, and large dotfile caches." \
        "# Top files in $(basename "$userdir")'s home:\n  find ${userdir} -type f -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -20 | awk '{printf \"%7.1f MB  %s\\n\", \$1/1024/1024, \$2}'\n\n# Common caches to clear:\n  rm -rf ${userdir}.cache/pip\n  rm -rf ${userdir}.npm\n  rm -rf ${userdir}.cache/go\n  rm -rf ${userdir}.cargo/registry"
    fi
  done
fi

# ── 6. /tmp Analysis ─────────────────────────────────────────────────────────
TMP_MB=$(size_mb /tmp)
if (( TMP_MB >= DIR_WARN_MB )); then
  section "/tmp  [$(hsize "$TMP_MB")]  — drilling in"
  echo "  Largest files in /tmp:"
  find /tmp -type f -printf '%s\t%p\n' 2>/dev/null \
    | sort -rn | head -15 \
    | awk '{printf "    %7.1f MB  %s\n", $1/1024/1024, $2}'
  add_rec "MEDIUM" \
    "/tmp is ${TMP_MB}MB" \
    "/tmp should be ephemeral. Large files here are usually abandoned job outputs, extracted archives, or runaway processes. Anything old is safe to delete." \
    "# Files in /tmp older than 7 days:\n  find /tmp -type f -atime +7 -ls\n\n# Delete files older than 7 days:\n  find /tmp -type f -atime +7 -delete\n\n# See which processes have files open in /tmp (don't delete those):\n  lsof +D /tmp 2>/dev/null | awk 'NR>1 {print \$1, \$9}' | sort -u"
fi

# ── 7. /usr Analysis (old kernels) ───────────────────────────────────────────
USR_MB=$(size_mb /usr)
if (( USR_MB >= 2000 )); then
  section "/usr  [$(hsize "$USR_MB")]"
  # Old kernels
  KERNEL_COUNT=$(ls /boot/vmlinuz-* 2>/dev/null | wc -l)
  RUNNING_KERNEL=$(uname -r)
  note "Running kernel: $RUNNING_KERNEL"
  note "Installed kernels: $KERNEL_COUNT"
  if (( KERNEL_COUNT >= 3 )); then
    finding "${KERNEL_COUNT} kernel versions installed — old ones can be removed"
    ls /boot/vmlinuz-* 2>/dev/null | sed 's|/boot/vmlinuz-||' | awk '{print "    "$0}'
    add_rec "LOW" \
      "${KERNEL_COUNT} kernel versions installed" \
      "Each old kernel package keeps headers, modules, and initramfs — typically 300-600MB each. autoremove handles this safely." \
      "# Automatically remove old kernels (keeps current + 1 previous):\n  apt-get autoremove --purge\n\n# To see exactly what would be removed:\n  apt-get --dry-run autoremove"
  fi

  USRLIB_MB=$(size_mb /usr/lib)
  note "/usr/lib: $(hsize "$USRLIB_MB")"
fi

# ── 8. Core dumps (system-wide) ──────────────────────────────────────────────
COREDUMP_MB=$(size_mb /var/lib/systemd/coredump)
if (( COREDUMP_MB >= 50 )); then
  section "systemd Core Dumps  [$(hsize "$COREDUMP_MB")]"
  coredumpctl list 2>/dev/null | tail -n 20 || ls -lh /var/lib/systemd/coredump/ 2>/dev/null || true
  add_rec "MEDIUM" \
    "systemd core dumps: ${COREDUMP_MB}MB in /var/lib/systemd/coredump" \
    "Core dumps pile up after process crashes. Review them if you're debugging, otherwise clean up." \
    "# List core dumps with context:\n  coredumpctl list\n\n# Remove all core dumps:\n  coredumpctl clean\n# Or directly:\n  rm -f /var/lib/systemd/coredump/*\n\n# To prevent future accumulation, cap core dump storage:\n  echo 'Storage=none' >> /etc/systemd/coredump.conf\n  systemctl daemon-reload"
fi

# ── 9. Large files system-wide ───────────────────────────────────────────────
section "Large Files System-Wide  (≥ ${LARGE_FILE_GB}GB)"
echo "  Scanning..."
LARGE_COUNT=$(find / -xdev \
  -not \( -path "/proc/*" -o -path "/sys/*" -o -path "/dev/*" \) \
  -type f -size +"${LARGE_FILE_GB}G" \
  -printf '%s\t%p\n' 2>/dev/null \
  | sort -rn \
  | tee /tmp/_disk_audit_large.tmp \
  | head -n "$TOP_N" \
  | awk '{printf "  %7.2f GB  %s\n", $1/1024/1024/1024, $2}' \
  | tee /dev/stderr | wc -l) 2>&1 || true

if [[ -s /tmp/_disk_audit_large.tmp ]]; then
  cat /tmp/_disk_audit_large.tmp | sort -rn | head -n "$TOP_N" \
    | awk '{printf "  %7.2f GB  %s\n", $1/1024/1024/1024, $2}'
else
  ok "No files ≥ ${LARGE_FILE_GB}GB found."
fi
rm -f /tmp/_disk_audit_large.tmp

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
      "Inode exhaustion risk on $mnt (${pct}% used)" \
      "When inodes are exhausted no new files can be created even if bytes are free. Usually caused by thousands of tiny files (logs, sessions, cache entries, mail spools)." \
      "# Find top directories by inode count:\n  for d in /var /tmp /home /root /opt; do\n    echo \"\$(find \$d -xdev 2>/dev/null | wc -l) inodes  \$d\"\n  done | sort -rn\n\n# Once you've found the dir, see what's inside:\n  ls /path/to/dir | wc -l\n\n# Common culprit — php session files:\n  find /var/lib/php -type f | wc -l\n  find /var/lib/php -type f -atime +1 -delete"
  fi
done < <(df -i 2>/dev/null | grep -Ev "^(Filesystem|tmpfs|udev|devtmpfs)")

# ── 11. Journal / APT summary ────────────────────────────────────────────────
section "systemd Journal"
if command -v journalctl &>/dev/null; then
  journalctl --disk-usage
fi

# ══════════════════════════════════════════════════════════════════════════════
# ── ACTION PLAN ──────────────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════════

if [[ ${#RECS[@]} -eq 0 ]]; then
  section "Action Plan"
  ok "No significant issues found. Disk usage looks healthy."
  echo ""
  echo -e "${BOLD}Done.${RESET}"
  exit 0
fi

echo ""
echo -e "${BOLD}${MAGENTA}╔══════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${MAGENTA}║              ACTION PLAN                             ║${RESET}"
echo -e "${BOLD}${MAGENTA}╚══════════════════════════════════════════════════════╝${RESET}"
echo -e "  ${RED}■ HIGH${RESET}   — address now, space at risk"
echo -e "  ${YELLOW}■ MEDIUM${RESET} — address soon, meaningful savings"
echo -e "  ${GREEN}■ LOW${RESET}   — housekeeping, minor gains"

priority_order=("HIGH" "MEDIUM" "LOW")

for pri in "${priority_order[@]}"; do
  printed_header=0
  for rec in "${RECS[@]}"; do
    IFS='|||' read -r p title explanation commands <<< "$rec"
    [[ "$p" != "$pri" ]] && continue

    if [[ $printed_header -eq 0 ]]; then
      echo ""
      case "$pri" in
        HIGH)   echo -e "  ${RED}${BOLD}── HIGH PRIORITY ──────────────────────────────────${RESET}" ;;
        MEDIUM) echo -e "  ${YELLOW}${BOLD}── MEDIUM PRIORITY ────────────────────────────────${RESET}" ;;
        LOW)    echo -e "  ${GREEN}${BOLD}── LOW PRIORITY ───────────────────────────────────${RESET}" ;;
      esac
      printed_header=1
    fi

    echo ""
    case "$pri" in
      HIGH)   echo -e "  ${RED}▶${RESET} ${BOLD}${title}${RESET}" ;;
      MEDIUM) echo -e "  ${YELLOW}▶${RESET} ${BOLD}${title}${RESET}" ;;
      LOW)    echo -e "  ${GREEN}▶${RESET} ${BOLD}${title}${RESET}" ;;
    esac
    echo -e "    ${explanation}"
    echo ""
    echo -e "    ${BOLD}Commands:${RESET}"
    echo "$commands" | sed 's/^/    /'
  done
done

echo ""
echo -e "${BOLD}Done. Re-run this script after each fix to track progress.${RESET}"
