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
# Cross-distro, non-interactive system updater with logging and dry-run.

set -euo pipefail

LOGFILE="/var/log/os_update.log"

# If interactive TTY, mirror output to screen + log; otherwise log only
if [[ -t 1 ]]; then
  exec > >(tee -a "$LOGFILE") 2>&1
else
  exec >>"$LOGFILE" 2>&1
fi

# Support "--dry-run" argument or DRY_RUN=1 env
DRY_RUN=${DRY_RUN:-0}
for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=1
done

echo "===== $(date -Is) : Starting system update (dry-run=$DRY_RUN) ====="

# Prefer /etc/os-release
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release || true
fi

is_cmd() { command -v "$1" >/dev/null 2>&1; }

update_debian_like() {
  echo "[INFO] Detected Debian-like system. Using apt-get..."
  if (( DRY_RUN )); then
    echo "[DRY] apt-get update -y"
    echo "[DRY] apt-get -y dist-upgrade"
    echo "[DRY] apt-get -y autoremove --purge"
    echo "[DRY] apt-get -y autoclean"
    return 0
  fi
  export DEBIAN_FRONTEND=noninteractive
  # Be cautious with config prompts; prefer keeping existing config
  apt-get update -y
  apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade
  apt-get -y autoremove --purge
  apt-get -y autoclean
  # Optional reboot hint: Debian/Ubuntu create this file when needed
  if [[ "${AUTO_REBOOT:-0}" == "1" ]] && [[ -f /var/run/reboot-required ]]; then
    echo "[INFO] Reboot required. Rebooting now..."
    /sbin/shutdown -r +1 "Auto-reboot after updates"
  fi
  echo "[INFO] Debian-like update complete."
}

update_rhel_like() {
  local mgr=""
  if is_cmd dnf; then
    mgr="dnf"
    echo "[INFO] Detected RHEL-like system. Using dnf..."
    if (( DRY_RUN )); then
      echo "[DRY] dnf -y upgrade --refresh || dnf -y distro-sync --refresh"
      echo "[DRY] dnf -y autoremove"
      echo "[DRY] dnf -y clean all"
      return 0
    fi
    dnf -y upgrade --refresh || dnf -y distro-sync --refresh
    dnf -y autoremove || true
    dnf -y clean all || true
    # Auto-reboot if needed (needs-restarting is in dnf-utils or rpm-ostree variants may differ)
    if [[ "${AUTO_REBOOT:-0}" == "1" ]] && is_cmd needs-restarting; then
      if ! needs-restarting -r >/dev/null 2>&1; then
        echo "[INFO] Reboot required. Rebooting now..."
        /sbin/shutdown -r +1 "Auto-reboot after updates"
      fi
    fi
  elif is_cmd yum; then
    mgr="yum"
    echo "[INFO] Detected RHEL-like system. Using yum..."
    if (( DRY_RUN )); then
      echo "[DRY] yum -y update"
      echo "[DRY] yum -y autoremove"
      echo "[DRY] yum -y clean all"
      return 0
    fi
    yum -y update
    yum -y autoremove || true
    yum -y clean all || true
    if [[ "${AUTO_REBOOT:-0}" == "1" ]] && is_cmd needs-restarting; then
      if ! needs-restarting -r >/dev/null 2>&1; then
        echo "[INFO] Reboot required. Rebooting now..."
        /sbin/shutdown -r +1 "Auto-reboot after updates"
      fi
    fi
  else
    echo "[ERROR] Neither dnf nor yum found." >&2
    exit 2
  fi
  echo "[INFO] RHEL-like update complete via ${mgr}."
}

# Detect family
family=""
if [[ "${ID_LIKE:-}" =~ debian ]] || [[ "${ID:-}" =~ (debian|ubuntu|linuxmint|pop) ]]; then
  family="debian"
elif [[ "${ID_LIKE:-}" =~ (rhel|fedora) ]] || [[ "${ID:-}" =~ (rhel|centos|rocky|almalinux|ol|fedora) ]]; then
  family="rhel"
else
  if is_cmd apt-get; then family="debian"
  elif is_cmd dnf || is_cmd yum; then family="rhel"
  fi
fi

if [[ -z "$family" ]]; then
  echo "[ERROR] Could not determine distro family. Aborting." >&2
  exit 3
fi

if [[ "$family" == "debian" ]]; then
  update_debian_like
else
  update_rhel_like
fi

echo "[INFO] Kernel: $(uname -r)"
echo "===== $(date -Is) : Update finished (dry-run=$DRY_RUN) ====="
EOF

  chmod 0755 "$target"
  echo "[OK] Installed updater: $target"
}

install_update_command() {
  local bin="/usr/local/bin/update-system"
  cat > "$bin" <<"EOF"
#!/usr/bin/env bash
# One-shot convenience wrapper to run the updater now.
args=("$@")
if [[ $EUID -ne 0 ]]; then
  exec sudo /usr/local/sbin/os_update.sh "${args[@]}"
else
  exec /usr/local/sbin/os_update.sh "${args[@]}"
fi
EOF
  chmod 0755 "$bin"
  echo "[OK] Installed command: $bin"
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
  echo "Enter a time in 24h format **HH:MM**, or one of: morning / afternoon / evening / night"
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
        HH="${WHEN%:*}"; MM="${WHEN#*:}"
      else
        echo "Invalid time. Use HH:MM or a named period." >&2
        exit 11
      fi
    ;;
  esac

  CRON_MIN="$(printf '%02d' "$MM")"
  CRON_HR="$(printf '%02d' "$HH")"
  CRON_DOW="$DNUM"

  echo
  read -r -p "Auto-reboot if required packages update? [y/N] " REBOOT_ANS || true
  if [[ "${REBOOT_ANS,,}" == "y" ]]; then
    AUTO_REBOOT="1"
  else
    AUTO_REBOOT="0"
  fi
}

install_cron() {
  local cronfile="/etc/cron.d/os_auto_update"

  # Ensure log file exists and is writable
  touch /var/log/os_update.log
  chmod 0644 /var/log/os_update.log

  # Export AUTO_REBOOT in the cron environment
  cat > "$cronfile" <<EOF
# Auto system updates (managed by setup-auto-updates.sh)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
AUTO_REBOOT=$AUTO_REBOOT

$CRON_MIN $CRON_HR * * $CRON_DOW root /usr/local/sbin/os_update.sh
EOF

  # Ensure trailing newline for cron
  sed -n '$p' "$cronfile" >/dev/null

  chown root:root "$cronfile"
  chmod 0644 "$cronfile"
  echo "[OK] Cron installed: $cronfile"
  echo "[OK] Will run at $CRON_HR:$CRON_MIN on day $CRON_DOW (0=Sun ... 6=Sat)."
  [[ "$AUTO_REBOOT" == "1" ]] && echo "[OK] Auto-reboot: ENABLED" || echo "[OK] Auto-reboot: disabled"
  echo "    Log: /var/log/os_update.log"
}

maybe_offer_run() {
  echo
  read -r -p "Run an update now? [y/N] " RUNNOW || true
  if [[ "${RUNNOW,,}" == "y" ]]; then
    /usr/local/bin/update-system
  fi

  echo
  echo "To uninstall:"
  echo "  sudo rm -f /etc/cron.d/os_auto_update /usr/local/bin/update-system /usr/local/sbin/os_update.sh"
  echo "  sudo systemctl restart cron 2>/dev/null || sudo systemctl restart crond 2>/dev/null || true"
}

main() {
  require_root
  install_updater_script
  install_update_command
  read_schedule
  install_cron
  systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true
  maybe_offer_run
}

main "$@"
