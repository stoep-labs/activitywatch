#!/usr/bin/env bash
# Build, push, and deploy ActivityWatch (aw-server-rust) on stoep via the umbrella compose stack.
#
# Expects activitywatch-*.zip in REPO_ROOT (from CI artifact builds-ubuntu-24.04-py3.9).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${REGISTRY:-stoep.co.uk:5000}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
DOCKERDIR="${DOCKERDIR:-/home/mserver/docker}"
STOEP_ENV="${STOEP_ENV:-${DOCKERDIR}/.env}"
STOEP_COMPOSE="${STOEP_COMPOSE:-${DOCKERDIR}/docker-compose-stoep.yml}"
COMPOSE_SRC="${REPO_ROOT}/compose/stoep/aw.yml"
COMPOSE_TARGET="${DOCKERDIR}/compose/stoep/aw.yml"
STOEP_INCLUDE='compose/$HOSTNAME/aw.yml'
IMAGE="${REGISTRY}/aw:${IMAGE_TAG}"

# shellcheck source=scripts/lib/ensure-stoep-include.sh
source "${REPO_ROOT}/scripts/lib/ensure-stoep-include.sh"

[ -f "${COMPOSE_SRC}" ] || { echo "ERROR: ${COMPOSE_SRC} not found" >&2; exit 1; }
[ -f "${REPO_ROOT}/Dockerfile" ] || { echo "ERROR: ${REPO_ROOT}/Dockerfile not found" >&2; exit 1; }

shopt -s nullglob
ZIPS=("${REPO_ROOT}"/activitywatch-*.zip)
shopt -u nullglob
if [ "${#ZIPS[@]}" -eq 0 ]; then
  echo "ERROR: no activitywatch-*.zip in ${REPO_ROOT}" >&2
  echo "Download the builds-ubuntu-24.04-py3.9 artifact first." >&2
  exit 1
fi
if [ "${#ZIPS[@]}" -gt 1 ]; then
  echo "WARNING: multiple zips found; using ${ZIPS[0]}" >&2
fi

if docker info >/dev/null 2>&1; then DOCKER=(docker); else DOCKER=(sudo docker); fi

read_env_var() {
  local key="$1" file="$2" line="" val=""
  if [ -r "${file}" ]; then
    line="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "${file}" 2>/dev/null | tail -1)" || true
  elif command -v sudo >/dev/null 2>&1; then
    line="$(sudo grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "${file}" 2>/dev/null | tail -1)" || true
  fi
  [ -n "${line}" ] || return 1
  val="${line#*=}"
  val="${val#\"}"; val="${val%\"}"
  val="${val#\'}"; val="${val%\'}"
  printf '%s' "${val}"
}

cd "${REPO_ROOT}"

echo "=== Building ${IMAGE} ==="
DOCKER_BUILDKIT="${DOCKER_BUILDKIT:-1}" "${DOCKER[@]}" build \
  -t "${IMAGE}" .

echo "=== Pushing ${IMAGE} ==="
"${DOCKER[@]}" push "${IMAGE}"

echo "=== Copying compose to ${COMPOSE_TARGET} ==="
mkdir -p "$(dirname "${COMPOSE_TARGET}")" 2>/dev/null \
  || sudo mkdir -p "$(dirname "${COMPOSE_TARGET}")"
if cp "${COMPOSE_SRC}" "${COMPOSE_TARGET}" 2>/dev/null; then
  :
else
  sudo cp "${COMPOSE_SRC}" "${COMPOSE_TARGET}"
fi

ensure_stoep_include "${STOEP_INCLUDE}"

echo "=== Deploying aw (image already built/pushed; no compose build) ==="
COMPOSE=(sudo docker compose --profile all --env-file "${STOEP_ENV}" -f "${STOEP_COMPOSE}")
# Recreate only the aw service from the registry image. Data/config volumes are preserved.
"${COMPOSE[@]}" up -d --no-build --remove-orphans --pull always aw

echo "=== Recent logs ==="
"${COMPOSE[@]}" logs --tail=50 aw || true

DOMAIN="${DOMAINNAME_HS:-}"
if [ -z "${DOMAIN}" ]; then
  DOMAIN="$(read_env_var "DOMAINNAME_HS" "${STOEP_ENV}" || true)"
fi
if [ -n "${DOMAIN}" ]; then
  echo "=== Health check https://aw.${DOMAIN}/api/0/info ==="
  ok=0
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if curl -fsS --max-time 10 "https://aw.${DOMAIN}/api/0/info"; then
      echo
      ok=1
      break
    fi
    echo "attempt ${i}/10 failed; retrying..." >&2
    sleep 3
  done
  if [ "${ok}" != "1" ]; then
    echo "ERROR: health check failed after retries" >&2
    "${COMPOSE[@]}" ps aw || true
    "${DOCKER[@]}" inspect aw --format '{{json .Config.Labels}}' || true
    exit 1
  fi
fi

echo "=== Deploy complete ==="
