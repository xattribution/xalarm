# syntax=docker/dockerfile:1.7
# xalarm — build the Android APK and serve it as a static download site.
#
# Stage 1 compiles the APK from source (Flutter + Android SDK + JDK all live
# in the builder image — the host only needs Docker). Stage 2 is a tiny nginx
# image serving the download page + the freshly built APK.
#
# Build args (injected by update.sh / docker-compose):
#   BUILD_COMMIT  short git commit of the source being built
#   BUILD_DATE    UTC timestamp of the build
#
# Build secrets (never baked into a layer; see docs/signing.md):
#   sideload_props  sideload.properties (storeFile must be /keys/sideload.jks)
#   sideload_jks    the sideload keystore

# ---------------------------------------------------------------------------
# Stage 1: build the APK
# ---------------------------------------------------------------------------
# `stable` tracks the latest stable Flutter. Override FLUTTER_IMAGE_TAG to
# pin a specific version.
ARG FLUTTER_IMAGE_TAG=stable
FROM ghcr.io/cirruslabs/flutter:${FLUTTER_IMAGE_TAG} AS builder

# Baked into the APK so the app can compare itself against the server's
# version.json and offer in-app updates.
ARG BUILD_COMMIT=dev
ARG BUILD_DATE=unknown

# The sideload channel has its own application id so it can be installed
# alongside the Play Store build (different signing keys can't upgrade each
# other anyway). Pass --build-arg APP_ID_SUFFIX= for a plain com.xalarm.
ARG APP_ID_SUFFIX=.sideload
ENV XALARM_APP_ID_SUFFIX=${APP_ID_SUFFIX}

WORKDIR /src

# Dependency resolution first, so source-only changes reuse this layer.
COPY pubspec.yaml pubspec.lock ./
COPY packages/recurrence_engine/pubspec.yaml packages/recurrence_engine/
COPY packages/sync_protocol/pubspec.yaml packages/sync_protocol/
RUN flutter pub get || true   # best-effort warmup; real resolve runs below

COPY . .

RUN flutter pub get

# Deploy gates: a broken engine, protocol, or analyzer error must fail the
# build, not ship.
RUN cd packages/recurrence_engine && dart pub get && dart test
RUN cd packages/sync_protocol && dart pub get && dart test
RUN flutter analyze --no-fatal-infos
RUN flutter test

# The signing key is mounted only for this step and never written to a layer.
RUN --mount=type=secret,id=sideload_props,target=/keys/sideload.properties \
    --mount=type=secret,id=sideload_jks,target=/keys/sideload.jks \
    XALARM_SIGNING_PROPERTIES=/keys/sideload.properties \
    flutter build apk --release \
      --dart-define=BUILD_COMMIT=$BUILD_COMMIT \
      --dart-define=BUILD_DATE=$BUILD_DATE

# ---------------------------------------------------------------------------
# Stage 2: serve the APK + download page
# ---------------------------------------------------------------------------
FROM nginx:alpine

ARG BUILD_COMMIT=dev
ARG BUILD_DATE=unknown

COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY deploy/site/ /usr/share/nginx/html/
COPY --from=builder /src/build/app/outputs/flutter-apk/app-release.apk \
     /usr/share/nginx/html/xalarm.apk

RUN printf '{"app":"xalarm","commit":"%s","date":"%s","file":"xalarm.apk"}\n' \
      "$BUILD_COMMIT" "$BUILD_DATE" > /usr/share/nginx/html/version.json

EXPOSE 80
