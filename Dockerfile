# xalarm — build the Android APK and serve it as a static download site.
#
# Stage 1 compiles the APK from source (Flutter + Android SDK + JDK all live
# in the builder image — the host only needs Docker). Stage 2 is a tiny nginx
# image serving the download page + the freshly built APK.
#
# Build args (injected by update.sh / docker-compose):
#   BUILD_COMMIT  short git commit of the source being built
#   BUILD_DATE    UTC timestamp of the build

# ---------------------------------------------------------------------------
# Stage 1: build the APK
# ---------------------------------------------------------------------------
# `stable` tracks the latest stable Flutter (>= 3.44.6 / Dart 3.12.2, which
# this app requires). Override FLUTTER_IMAGE_TAG to pin a specific version.
ARG FLUTTER_IMAGE_TAG=stable
FROM ghcr.io/cirruslabs/flutter:${FLUTTER_IMAGE_TAG} AS builder

WORKDIR /src

# Dependency resolution first, so source-only changes reuse this layer.
COPY pubspec.yaml pubspec.lock ./
COPY packages/recurrence_engine/pubspec.yaml packages/recurrence_engine/
RUN flutter pub get || true   # best-effort warmup; real resolve runs below

COPY . .

RUN flutter pub get

# Deploy gate: a broken recurrence engine must fail the build, not ship.
RUN cd packages/recurrence_engine && dart pub get && dart test

RUN flutter build apk --release

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
