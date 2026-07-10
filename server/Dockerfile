# xalarm sync relay — build context is the REPO ROOT (needs packages/).
FROM dart:stable AS build
WORKDIR /app
COPY packages/sync_protocol packages/sync_protocol
COPY server server
WORKDIR /app/server
RUN dart pub get
RUN dart compile exe bin/server.dart -o bin/server

# Minimal runtime: Dart AOT needs only the runtime libs from the SDK image.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server/bin/server /app/bin/server
EXPOSE 8080
CMD ["/app/bin/server"]
