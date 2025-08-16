#!/usr/bin/env bash
# setup-auto-updates.sh
# Installs a cross-distro updater and schedules it via cron.

set -euo pipefail

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root (e.g., sudo bash $0)" >&2
    exit 1
  fi
}

install_updater_script() {
  local target="/usr/local/sbin/os_update.sh"
  cat > "$target" <<"EOF"
#!/usr/bin/env bash
# /usr/local/sbin/os_update.sh
# Cross-distro, non-interactive system updater with logging.

set -euo pipefail

LOGFILE="/var/log/os_update.log"
exec >>"$LOGFILE" 2>&1

echo "===== $(date -Is) : Starting system update ====="

# Prefer /etc/os-release, fall back gracefully
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release || true
fi

is_cmd() { command -v "$1" >/dev/null 2>&1; }

update_debian_like() {
  echo "[INFO] Detected Debian-like system. Using apt-get..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get -y dist-upgrade
  apt-get -y autoremove --purge
  apt-get -y autoclean
  echo "[INFO] Debian-like update complete."
}

update_rhel_like() {
  local mgr=""
  if is_cmd dnf; then
    mgr="dnf"
    echo "[INFO] Detected RHEL-like system. Using dnf..."
    dnf -y upgrade --refresh || dnf -y distro-sync --refresh
    dnf -y autoremove || true
    dnf -y clean all || true
  elif is_cmd yum; then
    mgr="yum"
    echo "[INFO] Detected RHEL-like system. Using yum..."
    yum -y update
    yum -y autoremove || true
    yum -y clean all || true
  else
    echo "[ERROR] Neither dnf nor yum found." >&2
    exit 2
  fi
  echo "[INFO] RHEL-like update complete via ${mgr}."
}

# Heuristics to decide family
family=""
if [[ "${ID_LIKE:-}" =~ debian ]] || [[ "${ID:-}" =~ (debian|ubuntu) ]]; then
  family="debian"
elif [[ "${ID_LIKE:-}" =~ (rhel|fedora) ]] || [[ "${ID:-}" =~ (rhel|centos|rocky|almalinux|ol|fedora) ]]; then
  family="rhel"
else
  # Fallback by package manager presence
  if is_cmd apt-get; then family="debian"
  elif is_cmd dnf || is_cmd yum; then family="rhel"
  fi
fi

if [[ -z "$family" ]]; then
  echo "[ERROR] Could not determine distro family. Aborting." >&2
  exit 3
fi

# Run the appropriate updater
if [[ "$family" == "debian" ]]; then
  update_debian_like
else
  update_rhel_like
fi

echo "[INFO] Kernel: $(uname -r)"
echo "===== $(date -Is) : Update finished ====="
EOF

  chmod 0755 "$target"
  echo "[OK] Installed updater: $target"
}

install_update_command() {
  local bin="/usr/local/bin/update-system"
  cat > "$bin" <<"EOF"
#!/usr/bin/env bash
# One-shot convenience wrapper to run the updater now.
if [[ $EUID -ne 0 ]]; then
  exec sudo /usr/local/sbin/os_update.sh
else
  exec /usr/local/sbin/os_update.sh
fi
EOF
  chmod 0755 "$bin"
  echo "[OK] Installed command: $bin  (run it any time to update now)"
}

read_schedule() {
  echo
  echo "== Auto-Update Schedule =="
  echo "Enter the day of the week (mon,tue,wed,thu,fri,sat,sun or 0-6; 0/7=Sun):"
  read -r DOW_IN

  # Normalize day of week to cron numeric (0-6, where 0/7=Sun)
  local DNUM
  case "${DOW_IN,,}" in
    0|7|sun|sunday) DNUM=0 ;;
    1|mon|monday)   DNUM=1 ;;
    2|tue|tuesday)  DNUM=2 ;;
    3|wed|wednesday) DNUM=3 ;;
    4|thu|thursday) DNUM=4 ;;
    5|fri|friday)   DNUM=5 ;;
    6|sat|saturday) DNUM=6 ;;
    *) echo "Invalid day. Try again."; exit 10 ;;
  esac

  echo
  echo "Enter a time (24h HH:MM), or one of: morning / afternoon / evening / night"
  echo "  morning=09:00, afternoon=14:00, evening=19:00, night=02:00"
  read -r WHEN

  local HH=""; local MM=""
  case "${WHEN,,}" in
    morning)  HH=09; MM=00 ;;
    afternoon) HH=14; MM=00 ;;
    evening)  HH=19; MM=00 ;;
    night)    HH=02; MM=00 ;;
    *)
      if [[ "$WHEN" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]]; then
        HH="${WHEN%:*}"
        MM="${WHEN#*:}"
      else
        echo "Invalid time. Use HH:MM or a named period." >&2
        exit 11
      fi
    ;;
  esac

  CRON_MIN="$MM"
  CRON_HR="$HH"
  CRON_DOW="$DNUM"
}

install_cron() {
  local cronfile="/etc/cron.d/os_auto_update"

  # Ensure log file exists and is writable
  touch /var/log/os_update.log
  chmod 0644 /var/log/os_update.log

  cat > "$cronfile" <<EOF
# Auto system updates (managed by setup-auto-updates.sh)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

$CRON_MIN $CRON_HR * * $CRON_DOW root /usr/local/sbin/os_update.sh
EOF

  chmod 0644 "$cronfile"
  echo "[OK] Cron installed: $cronfile"
  echo "[OK] Will run at $CRON_HR:$CRON_MIN on day $CRON_DOW (0=Sun ... 6=Sat)."
  echo "    Log: /var/log/os_update.log"
}

maybe_offer_uninstall() {
  echo
  echo "Installation complete. Do you want to run an update now? [y/N]"
  read -r RUNNOW
  if [[ "${RUNNOW,,}" == "y" ]]; then
    /usr/local/bin/update-system
  fi

  echo
  echo "To uninstall later, run:"
  echo "  sudo rm -f /etc/cron.d/os_auto_update /usr/local/bin/update-system /usr/local/sbin/os_update.sh"
  echo "  sudo systemctl restart cron 2>/dev/null || sudo systemctl restart crond 2>/dev/null || true"
}

main() {
  require_root
  install_updater_script
  install_update_command
  read_schedule
  install_cron
  # Try to nudge cron to reload (usually not required for /etc/cron.d)
  systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true
  maybe_offer_uninstall
}

main "$@"
