#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/patchpilot"
CONFIG_FILE="/etc/patchpilot.env"
STATE_DIR="/var/lib/patchpilot"
LOG_DIR="/var/log/patchpilot"
SERVICE_USER="patchpilot"
PORT="4128"
AUTO_UPDATE="disabled"
AUTO_UPDATE_HOUR="2"
SKIP_OS_PACKAGES="0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: sudo bash server-app/install.sh [options]

Options:
  --port 4128
  --install-dir /opt/patchpilot
  --config-file /etc/patchpilot.env
  --state-dir /var/lib/patchpilot
  --log-dir /var/log/patchpilot
  --user patchpilot
  --auto-update daily|disabled
  --auto-update-hour 2
  --skip-os-packages
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="${2:-}"; shift 2 ;;
    --install-dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --config-file) CONFIG_FILE="${2:-}"; shift 2 ;;
    --state-dir) STATE_DIR="${2:-}"; shift 2 ;;
    --log-dir) LOG_DIR="${2:-}"; shift 2 ;;
    --user) SERVICE_USER="${2:-}"; shift 2 ;;
    --auto-update) AUTO_UPDATE="${2:-}"; shift 2 ;;
    --auto-update-hour) AUTO_UPDATE_HOUR="${2:-}"; shift 2 ;;
    --skip-os-packages) SKIP_OS_PACKAGES="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

[[ "${EUID}" -eq 0 ]] || { echo "Run this installer with sudo." >&2; exit 1; }
[[ "${PORT}" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || { echo "Invalid port: ${PORT}" >&2; exit 1; }
[[ "${AUTO_UPDATE_HOUR}" =~ ^[0-9]+$ ]] && (( AUTO_UPDATE_HOUR <= 23 )) || { echo "Invalid update hour." >&2; exit 1; }
[[ "${AUTO_UPDATE}" == "daily" || "${AUTO_UPDATE}" == "disabled" ]] || { echo "Use --auto-update daily or disabled." >&2; exit 1; }

for required in index.html server.py patchscope.sh VERSION assets server-app/upgrade.sh server-app/auto_update.sh; do
  [[ -e "${SOURCE_DIR}/${required}" ]] || { echo "Package is missing ${required}." >&2; exit 1; }
done

if [[ "${SKIP_OS_PACKAGES}" != "1" ]]; then
  packages=()
  command -v python3 >/dev/null 2>&1 || packages+=(python3)
  command -v curl >/dev/null 2>&1 || packages+=(curl)
  command -v tar >/dev/null 2>&1 || packages+=(tar)
  command -v sshpass >/dev/null 2>&1 || packages+=(sshpass)
  if ! command -v ssh >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      packages+=(openssh-client)
    else
      packages+=(openssh-clients)
    fi
  fi

  if (( ${#packages[@]} > 0 )); then
    if command -v dnf >/dev/null 2>&1; then
      dnf install -y "${packages[@]}"
    elif command -v yum >/dev/null 2>&1; then
      yum install -y "${packages[@]}"
    elif command -v apt-get >/dev/null 2>&1; then
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
    else
      echo "Install these required packages and retry: ${packages[*]}" >&2
      exit 1
    fi
  else
    echo "Required OS commands are already installed; skipping package-manager changes."
  fi
fi

command -v python3 >/dev/null 2>&1 || { echo "Python 3 is required." >&2; exit 1; }
command -v ssh >/dev/null 2>&1 || { echo "OpenSSH client is required." >&2; exit 1; }

if ! id -u "${SERVICE_USER}" >/dev/null 2>&1; then
  useradd --system --create-home --shell /usr/sbin/nologin "${SERVICE_USER}"
fi

mkdir -p "${INSTALL_DIR}" "${STATE_DIR}" "${LOG_DIR}"
tar --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' \
  -C "${SOURCE_DIR}" -cf - index.html server.py patchscope.sh VERSION README.md assets server-app \
  | tar -C "${INSTALL_DIR}" -xf -
chmod +x "${INSTALL_DIR}/patchscope.sh" "${INSTALL_DIR}/server-app/"*.sh

if [[ ! -f "${CONFIG_FILE}" ]]; then
  cat > "${CONFIG_FILE}" <<EOF
PATCHSCOPE_HOST=0.0.0.0
PATCHSCOPE_PORT=${PORT}
PATCHSCOPE_SSH_CONNECT_TIMEOUT=90
PATCHSCOPE_SSH_TIMEOUT_GRACE=30
PATCHPILOT_STATE_DIR=${STATE_DIR}
PATCHPILOT_LOG_DIR=${LOG_DIR}
PATCHPILOT_GITHUB_OWNER=reply4ramesh
PATCHPILOT_GITHUB_REPO=PatchPilot
PATCHPILOT_GITHUB_BRANCH=main
NO_PROXY=localhost,127.0.0.1
no_proxy=localhost,127.0.0.1
EOF
else
  sed -i "s/^PATCHSCOPE_PORT=.*/PATCHSCOPE_PORT=${PORT}/" "${CONFIG_FILE}"
  grep -q '^NO_PROXY=' "${CONFIG_FILE}" || printf '%s\n' 'NO_PROXY=localhost,127.0.0.1' >> "${CONFIG_FILE}"
  grep -q '^no_proxy=' "${CONFIG_FILE}" || printf '%s\n' 'no_proxy=localhost,127.0.0.1' >> "${CONFIG_FILE}"
fi

cat > /etc/systemd/system/patchpilot.service <<EOF
[Unit]
Description=PatchPilot Oracle patch orchestration
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=-${CONFIG_FILE}
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/server.py
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/patchpilot-updater.service <<EOF
[Unit]
Description=PatchPilot GitHub updater
After=network-online.target patchpilot.service

[Service]
Type=oneshot
EnvironmentFile=-${CONFIG_FILE}
ExecStart=/bin/bash ${INSTALL_DIR}/server-app/auto_update.sh
EOF

cat > /etc/systemd/system/patchpilot-updater.timer <<EOF
[Unit]
Description=Check PatchPilot GitHub updates daily

[Timer]
OnCalendar=*-*-* ${AUTO_UPDATE_HOUR}:00:00
Persistent=true
RandomizedDelaySec=15m

[Install]
WantedBy=timers.target
EOF

chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}" "${STATE_DIR}" "${LOG_DIR}"
chmod 640 "${CONFIG_FILE}"
systemctl daemon-reload
systemctl enable --now patchpilot.service
if [[ "${AUTO_UPDATE}" == "daily" ]]; then
  systemctl enable --now patchpilot-updater.timer
else
  systemctl disable --now patchpilot-updater.timer 2>/dev/null || true
fi

for _ in {1..20}; do
  curl --noproxy '*' -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null && break
  sleep 1
done
curl --noproxy '*' -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null

HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo
echo "PatchPilot $(cat "${INSTALL_DIR}/VERSION") is running."
echo "Open: http://${HOST_IP:-$(hostname)}:${PORT}/"
echo "Config: ${CONFIG_FILE}"
echo "Logs: journalctl -u patchpilot -f"
