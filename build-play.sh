#!/usr/bin/env bash
#
# xalarm — build a Play Store App Bundle (AAB) via Docker.
#
# Like update.sh, this needs no local Flutter install: the build runs inside
# the same Flutter builder image. The AAB is signed with your PRIVATE upload
# key (never committed) and the Play build flag strips the self-update flow,
# as required by Play policy.
#
# One-time setup (see docs/play_store.md for details):
#   1. Generate an upload keystore:
#        keytool -genkeypair -v -keystore upload.jks -alias upload \
#          -keyalg RSA -keysize 2048 -validity 10000
#      (or with openssl if you have no JDK — see the docs)
#   2. Put upload.jks somewhere private, e.g. ~/xalarm-keys/upload.jks
#   3. Create ~/xalarm-keys/key.properties:
#        storeFile=/keys/upload.jks
#        storePassword=<yours>
#        keyAlias=upload
#        keyPassword=<yours>
#
# Usage:
#   XALARM_KEYS_DIR=~/xalarm-keys ./build-play.sh
#   → dist/xalarm-<version>.aab
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${XALARM_KEYS_DIR:-$HOME/xalarm-keys}"
IMAGE="${XALARM_FLUTTER_IMAGE:-ghcr.io/cirruslabs/flutter:stable}"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null || die "Docker is required."
[ -f "$KEYS_DIR/key.properties" ] ||
  die "No $KEYS_DIR/key.properties — see docs/play_store.md for one-time setup."
[ -f "$SCRIPT_DIR/pubspec.yaml" ] || die "Run this from the xalarm repo root."

mkdir -p "$SCRIPT_DIR/dist"

BUILD_COMMIT="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo release)"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VERSION="$(grep '^version:' "$SCRIPT_DIR/pubspec.yaml" | awk '{print $2}')"

say "Building Play bundle for xalarm $VERSION (commit $BUILD_COMMIT)…"

# The keystore dir mounts at /keys; key.properties' storeFile must use the
# /keys/... path. A named volume caches pub packages between runs.
docker run --rm \
  -v "$SCRIPT_DIR":/src \
  -v "$KEYS_DIR":/keys:ro \
  -v xalarm-play-pub-cache:/root/.pub-cache \
  -w /src \
  "$IMAGE" \
  bash -c "
    set -e
    cp /keys/key.properties android/key.properties
    flutter pub get
    flutter build appbundle --release \
      --dart-define=PLAY_STORE=true \
      --dart-define=BUILD_COMMIT=$BUILD_COMMIT \
      --dart-define=BUILD_DATE=$BUILD_DATE
    rm -f android/key.properties
  "

cp "$SCRIPT_DIR/build/app/outputs/bundle/release/app-release.aab" \
   "$SCRIPT_DIR/dist/xalarm-$VERSION.aab"

say "Done: dist/xalarm-$VERSION.aab"
echo "  Upload it in Play Console → your app → (Internal) testing → Create release."
