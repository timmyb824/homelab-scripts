#!/usr/bin/env bash
# disk-audit.sh — Disk usage analysis for Prometheus LXC
# Usage: sudo bash disk-audit.sh [--top N] [--threshold GB]

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
TOP_N="${2:-20}"          # Number of largest items to show (default: 20)
THRESHOLD_GB="${4:-1}"    # Min size in GB for "large files" scan (default: 1)
PROMETHEUS_DATA="${PROMETHEUS_DATA:-/var/lib/prometheus}"

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --top)       TOP_N="$2";       shift 2 ;;
    --threshold) THRESHOLD_GB="$2"; shift 2 ;;
    *)           shift ;;
  esac
done

# ── Helpers ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; RESET='\033[0m'

section() { echo -e "\n${BOLD}${CYAN}━━━  $1  ━━━${RESET}"; }
warn()    { echo -e "${YELLOW}⚠  $1${RESET}"; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root (or with sudo).${RESET}"
    exit 1
  fi
}

# ── Main ─────────────────────────────────────────────────────────────────────
require_root

echo -e "${BOLD}Disk Audit — $(hostname) — $(date '+%Y-%m-%d %H:%M:%S')${RESET}"

# ── 1. Overall disk usage ────────────────────────────────────────────────────
section "Overall Disk Usage"
df -h --output=source,fstype,size,used,avail,pcent,target \
  | grep -v tmpfs | grep -v udev | grep -v devtmpfs

# ── 2. Top-level directory breakdown (/) ─────────────────────────────────────
section "Top-Level Directory Sizes ( / )"
du -h --max-depth=1 / 2>/dev/null \
  | grep -v "^0" \
  | sort -rh \
  | head -n "$TOP_N"

# ── 3. Common high-usage locations ───────────────────────────────────────────
section "Common High-Usage Locations"

check_dir() {
  local dir="$1"
  local label="${2:-$1}"
  if [[ -d "$dir" ]]; then
    local size
    size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
    printf "  %-40s %s\n" "$label" "$size"
  else
    printf "  %-40s %s\n" "$label" "(not found)"
  fi
}

check_dir /var/log              "Logs (/var/log)"
check_dir /var/lib/prometheus   "Prometheus data (/var/lib/prometheus)"
check_dir /var/lib/prometheus2  "Prometheus data (/var/lib/prometheus2)"
check_dir /tmp                  "Temp (/tmp)"
check_dir /var/cache            "Package cache (/var/cache)"
check_dir /var/lib/apt          "APT state (/var/lib/apt)"
check_dir /root                 "Root home (/root)"
check_dir /home                 "User homes (/home)"
check_dir /opt                  "Optional packages (/opt)"
check_dir /usr/local            "Local installs (/usr/local)"

# ── 4. Log directory breakdown ───────────────────────────────────────────────
section "/var/log Breakdown"
if [[ -d /var/log ]]; then
  du -h --max-depth=2 /var/log 2>/dev/null \
    | grep -v "^0" \
    | sort -rh \
    | head -n "$TOP_N"
else
  warn "/var/log not found"
fi

# ── 5. Old/rotated logs ───────────────────────────────────────────────────────
section "Old & Rotated Log Files"
find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.old" -o -name "*.bak" \) \
  -printf '%s\t%p\n' 2>/dev/null \
  | sort -rn \
  | head -n "$TOP_N" \
  | awk '{printf "  %s\t%s\n", $1/1024/1024 " MB", $2}'

# ── 6. Prometheus-specific: TSDB blocks ───────────────────────────────────────
section "Prometheus TSDB Data"
if [[ -d "$PROMETHEUS_DATA" ]]; then
  echo -e "  Data dir: ${PROMETHEUS_DATA}"
  du -sh "$PROMETHEUS_DATA" 2>/dev/null | awk '{print "  Total:   " $1}'
  echo ""

  # Block breakdown
  if [[ -d "${PROMETHEUS_DATA}/chunks_head" ]]; then
    du -sh "${PROMETHEUS_DATA}/chunks_head" 2>/dev/null \
      | awk '{print "  chunks_head (in-memory block on disk): " $1}'
  fi

  echo ""
  echo "  TSDB blocks (oldest → newest):"
  find "$PROMETHEUS_DATA" -maxdepth 1 -mindepth 1 -type d \
    | sort \
    | while read -r block; do
        size=$(du -sh "$block" 2>/dev/null | awk '{print $1}')
        name=$(basename "$block")
        # Show meta.json minTime/maxTime if present
        if [[ -f "$block/meta.json" ]]; then
          min_t=$(python3 -c "
import json,sys,datetime
d=json.load(open('$block/meta.json'))
t=d.get('minTime',0)//1000
print(datetime.datetime.utcfromtimestamp(t).strftime('%Y-%m-%d'))
" 2>/dev/null || echo "?")
          max_t=$(python3 -c "
import json,sys,datetime
d=json.load(open('$block/meta.json'))
t=d.get('maxTime',0)//1000
print(datetime.datetime.utcfromtimestamp(t).strftime('%Y-%m-%d'))
" 2>/dev/null || echo "?")
          printf "    %-30s %6s   [%s → %s]\n" "$name" "$size" "$min_t" "$max_t"
        else
          printf "    %-30s %6s\n" "$name" "$size"
        fi
      done

  # WAL size
  if [[ -d "${PROMETHEUS_DATA}/wal" ]]; then
    wal_size=$(du -sh "${PROMETHEUS_DATA}/wal" 2>/dev/null | awk '{print $1}')
    echo -e "\n  WAL size: ${wal_size}"
    warn "WAL > 1GB often indicates a compaction issue or high cardinality."
  fi

  # Retention hint
  echo ""
  echo "  Tip: Check your --storage.tsdb.retention.time and"
  echo "       --storage.tsdb.retention.size flags in your Prometheus unit:"
  echo "         systemctl cat prometheus | grep storage"
else
  warn "Prometheus data dir '${PROMETHEUS_DATA}' not found."
  warn "Set PROMETHEUS_DATA=/your/path before running to override."
fi

# ── 7. Large files system-wide ────────────────────────────────────────────────
section "Large Files System-Wide (≥ ${THRESHOLD_GB}GB)"
echo "  Scanning... (this may take a moment)"
find / \
  -xdev \
  -not -path "/proc/*" \
  -not -path "/sys/*" \
  -not -path "/dev/*" \
  -type f \
  -size +"${THRESHOLD_GB}G" \
  -printf '%s\t%p\n' 2>/dev/null \
  | sort -rn \
  | head -n "$TOP_N" \
  | awk '{printf "  %7.2f GB\t%s\n", $1/1024/1024/1024, $2}'

if ! find / -xdev -not -path "/proc/*" -not -path "/sys/*" -not -path "/dev/*" \
    -type f -size +"${THRESHOLD_GB}G" 2>/dev/null | grep -q .; then
  echo "  No files found ≥ ${THRESHOLD_GB}GB."
fi

# ── 8. Inode usage ────────────────────────────────────────────────────────────
section "Inode Usage (high inode use can fill a filesystem even with free space)"
df -i | grep -v tmpfs | grep -v udev | grep -v devtmpfs

# ── 9. Journal size ───────────────────────────────────────────────────────────
section "systemd Journal Size"
if command -v journalctl &>/dev/null; then
  journalctl --disk-usage
  echo ""
  echo "  To vacuum journals older than 7 days:  journalctl --vacuum-time=7d"
  echo "  To cap journal size to 200MB:          journalctl --vacuum-size=200M"
fi

# ── 10. APT cache ─────────────────────────────────────────────────────────────
section "APT Cache"
if command -v apt-get &>/dev/null; then
  du -sh /var/cache/apt/archives 2>/dev/null | awk '{print "  Cached packages: " $1}'
  echo "  To clean: apt-get clean"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
section "Quick Wins Checklist"
echo "  [ ] journalctl --vacuum-time=7d"
echo "  [ ] apt-get clean"
echo "  [ ] find /var/log -name '*.gz' -delete  (if rotated logs are large)"
echo "  [ ] Review Prometheus --storage.tsdb.retention.time (current data window)"
echo "  [ ] Review Prometheus --storage.tsdb.retention.size (size cap)"
echo "  [ ] Check for runaway exporters writing to /tmp or /var/lib"
echo ""
echo -e "${BOLD}Done.${RESET}"
