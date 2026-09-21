#!/usr/bin/env bash
#
# xalarm — update & (re)deploy the self-hosted APK download site.
#
# What it does:
#   1. pulls the latest source from GitHub
#   2. compiles the release APK from that source (inside the Docker image build)
#   3. (re)starts the web container serving the freshly built APK
#
# The only thing this host needs is Docker (with the Compose v2 plugin and
# BuildKit). Everything else — Flutter, JDK, Android SDK, Gradle — lives
# inside the build image.
#
# Signing: the APK is signed with a private key that lives OUTSIDE the repo
# (XALARM_KEYS_DIR, default ~/xalarm-keys next to the Play upload key). On
# the first run a key is generated for you; back that directory up — every
# future sideload build must use the same key or phones will refuse the
# update. See docs/signing.md.
#
# Usage:
#   ./update.sh                     # clone/update into ./xalarm and deploy
#   XALARM_WEB_PORT=50000 ./update.sh
#   XALARM_WEB_DIR=/srv/xalarm ./update.sh
#   XALARM_KEYS_DIR=/secure/keys ./update.sh
#
set -euo pipefail

REPO_URL="${XALARM_REPO_URL:-https://github.com/xattribution/xalarm.git}"
# NOTE: switch the default to `main` once the app is merged there.
BRANCH="${XALARM_BRANCH:-claude/panama-schedule-alarm-app-exj97n}"
# Default: clone next to wherever this script lives (survives running via
# sudo, where $HOME silently becomes /root). Override with XALARM_WEB_DIR.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="${XALARM_WEB_DIR:-$SCRIPT_DIR/xalarm}"
PORT="${XALARM_WEB_PORT:-49731}"
# Under sudo, $HOME becomes /root — resolve the invoking user's real home so
# the keys land where they can be found (and backed up) later.
REAL_HOME="$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)"
KEYS_DIR="${XALARM_KEYS_DIR:-${REAL_HOME:-$HOME}/xalarm-keys}"
IMAGE="${XALARM_FLUTTER_IMAGE:-ghcr.io/cirruslabs/flutter:stable}"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null    || die "git is required."
command -v docker >/dev/null || die "Docker is required — see https://docs.docker.com/engine/install/"
docker compose version >/dev/null 2>&1 || die "The Docker Compose v2 plugin is required (docker compose)."

# 0. make sure a sideload signing key exists (generated once, kept forever)
ensure_sideload_key() {
  if [ -f "$KEYS_DIR/sideload.jks" ] && [ -f "$KEYS_DIR/sideload.properties" ]; then
    return
  fi
  say "No sideload signing key in $KEYS_DIR — generating one (first run only)"
  mkdir -p "$KEYS_DIR"
  chmod 700 "$KEYS_DIR"
  local pass
  pass="$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 32)"
  docker run --rm -v "$KEYS_DIR":/keys "$IMAGE" \
    keytool -genkeypair -v -keystore /keys/sideload.jks -alias sideload \
      -keyalg RSA -keysize 2048 -validity 10000 \
      -storepass "$pass" -keypass "$pass" \
      -dname "CN=xalarm sideload, O=$(hostname)" >/dev/null
  umask 077
  cat > "$KEYS_DIR/sideload.properties" <<EOP
storeFile=/keys/sideload.jks
storePassword=$pass
keyAlias=sideload
keyPassword=$pass
EOP
  chmod 600 "$KEYS_DIR/sideload.properties" "$KEYS_DIR/sideload.jks"
  if [ -n "${SUDO_USER:-}" ]; then
    chown -R "$SUDO_USER" "$KEYS_DIR" 2>/dev/null || true
  fi
  echo
  echo "  A new signing key was created at $KEYS_DIR/sideload.jks."
  echo "  BACK IT UP. Phones only accept updates signed with this same key."
  echo
}
ensure_sideload_key

# 1. get / update the source
if [ -d "$DIR/.git" ]; then
  say "Updating source in $DIR"
  git -C "$DIR" fetch --prune origin "$BRANCH"
  git -C "$DIR" checkout -q "$BRANCH"
  git -C "$DIR" reset --hard "origin/$BRANCH"
else
  say "Cloning $REPO_URL into $DIR"
  git clone --branch "$BRANCH" "$REPO_URL" "$DIR"
fi

cd "$DIR"

# 2 + 3. compile the APK inside the image build, then (re)start the container
BUILD_COMMIT="$(git rev-parse --short HEAD)"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export BUILD_COMMIT BUILD_DATE XALARM_WEB_PORT="$PORT" XALARM_KEYS_DIR="$KEYS_DIR"
export DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1

say "Building image (this compiles the APK from source; the first run downloads the Flutter build image and Gradle deps — go get coffee)…"
docker compose build --pull

say "Starting the web container on port $PORT"
docker compose up -d --force-recreate

# tidy up the old dangling image layers from previous builds
docker image prune -f >/dev/null 2>&1 || true

say "Done."
echo
echo "  xalarm is live at:      http://localhost:${PORT}"
echo "  (from another device:   http://<this-host-ip>:${PORT})"
echo
echo "  Re-run ./update.sh anytime to pull the latest source, recompile, and redeploy."
