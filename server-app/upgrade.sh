#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/patchpilot"
CONFIG_FILE="/etc/patchpilot.env"
BACKUP_ROOT="/opt/patchpilot-backup"
ARCHIVE=""
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --config-file) CONFIG_FILE="${2:-}"; shift 2 ;;
    --backup-root) BACKUP_ROOT="${2:-}"; shift 2 ;;
    --archive) ARCHIVE="${2:-}"; shift 2 ;;
    -h|--help) echo "Usage: sudo bash upgrade.sh [--archive package.tar.gz]"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

cleanup() { [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]] && rm -rf "${TEMP_DIR}" || true; }
trap cleanup EXIT
[[ "${EUID}" -eq 0 ]] || { echo "Run this upgrade with sudo." >&2; exit 1; }
[[ -d "${INSTALL_DIR}" ]] || { echo "PatchPilot is not installed at ${INSTALL_DIR}." >&2; exit 1; }

if [[ -n "${ARCHIVE}" ]]; then
  [[ -f "${ARCHIVE}" ]] || { echo "Archive not found: ${ARCHIVE}" >&2; exit 1; }
  TEMP_DIR="$(mktemp -d)"
  tar -xzf "${ARCHIVE}" -C "${TEMP_DIR}"
  SOURCE_DIR="$(find "${TEMP_DIR}" -maxdepth 2 -type f -name VERSION -printf '%h\n' | head -n 1)"
fi

for required in index.html server.py patchscope.sh VERSION assets server-app/upgrade.sh; do
  [[ -e "${SOURCE_DIR}/${required}" ]] || { echo "Upgrade package is missing ${required}." >&2; exit 1; }
done

PORT="$(grep -E '^PATCHSCOPE_PORT=' "${CONFIG_FILE}" 2>/dev/null | tail -n 1 | cut -d= -f2 || true)"
PORT="${PORT:-4128}"
if curl -fsS "http://127.0.0.1:${PORT}/api/update-readiness" | grep -q '"ready": false'; then
  echo "PatchPilot has active patch jobs. Upgrade cancelled." >&2
  exit 1
fi

CURRENT_VERSION="$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo unknown)"
NEW_VERSION="$(cat "${SOURCE_DIR}/VERSION")"
STAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_DIR="${BACKUP_ROOT}/patchpilot-${CURRENT_VERSION}-${STAMP}"
STAGE_DIR="$(mktemp -d "${INSTALL_DIR}.stage.XXXXXX")"

tar --exclude='.git' --exclude='__pycache__' --exclude='*.pyc' \
  -C "${SOURCE_DIR}" -cf - index.html server.py patchscope.sh VERSION README.md assets server-app \
  | tar -C "${STAGE_DIR}" -xf -
python3 -m py_compile "${STAGE_DIR}/server.py"
chmod +x "${STAGE_DIR}/patchscope.sh" "${STAGE_DIR}/server-app/"*.sh

mkdir -p "${BACKUP_DIR}"
cp -a "${INSTALL_DIR}/." "${BACKUP_DIR}/"
systemctl stop patchpilot.service

rollback() {
  echo "Upgrade failed; restoring PatchPilot ${CURRENT_VERSION}." >&2
  rm -rf "${INSTALL_DIR}"
  mkdir -p "${INSTALL_DIR}"
  cp -a "${BACKUP_DIR}/." "${INSTALL_DIR}/"
  systemctl start patchpilot.service
}
trap rollback ERR

rm -rf "${INSTALL_DIR}"
mv "${STAGE_DIR}" "${INSTALL_DIR}"
systemctl start patchpilot.service
for _ in {1..20}; do
  curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null && break
  sleep 1
done
curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null
trap - ERR
echo "PatchPilot upgraded from ${CURRENT_VERSION} to ${NEW_VERSION}."
echo "Backup: ${BACKUP_DIR}"
