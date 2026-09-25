#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${PATCHPILOT_INSTALL_DIR:-/opt/patchpilot}"
OWNER="${PATCHPILOT_GITHUB_OWNER:-reply4ramesh}"
REPO="${PATCHPILOT_GITHUB_REPO:-PatchPilot}"
BRANCH="${PATCHPILOT_GITHUB_BRANCH:-main}"
CURRENT_VERSION="$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo unknown)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

VERSION_URL="https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}/VERSION"
ARCHIVE_URL="https://github.com/${OWNER}/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
CURL_ARGS=(-fsSL --connect-timeout 30 --retry 3)
if [[ -n "${PATCHPILOT_GITHUB_TOKEN:-}" ]]; then
  CURL_ARGS+=(-H "Authorization: Bearer ${PATCHPILOT_GITHUB_TOKEN}")
fi

REMOTE_VERSION="$(curl "${CURL_ARGS[@]}" "${VERSION_URL}" | tr -d '\r\n')"
if [[ -z "${REMOTE_VERSION}" || "${REMOTE_VERSION}" == "${CURRENT_VERSION}" ]]; then
  echo "PatchPilot is current at ${CURRENT_VERSION}."
  exit 0
fi

PORT="${PATCHSCOPE_PORT:-4128}"
if curl --noproxy '*' -fsS "http://127.0.0.1:${PORT}/api/update-readiness" | grep -q '"ready": false'; then
  echo "PatchPilot ${REMOTE_VERSION} is available, but active patch jobs prevent upgrading."
  exit 0
fi

ARCHIVE="${TEMP_DIR}/patchpilot-${REMOTE_VERSION}.tar.gz"
curl "${CURL_ARGS[@]}" "${ARCHIVE_URL}" -o "${ARCHIVE}"
bash "${INSTALL_DIR}/server-app/upgrade.sh" --archive "${ARCHIVE}"
