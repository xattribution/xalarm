# xalarm Time Sync — server setup

Time Sync pairs two xalarm apps with jackbox-style codes so a shared timer +
stopwatch stay in lockstep — either side can set/start/stop. The relay is a
tiny in-memory WebSocket server you self-host next to the download site.

## What the server stores

Nothing durable, by design:
- Self-chosen display names and 6-char session codes — RAM only.
- The last timer/stopwatch action per session (so a reconnect can restore
  state) — RAM only.
- When a session ends (either side disconnects and both don't hit Reconnect
  within 5 seconds), everything about it is purged. A server restart wipes
  all sessions.

No accounts, no logs of alarm data, no persistence.

## Deploying

`update.sh` already brings it up — the `sync` service in
`docker-compose.yml` builds from `server/Dockerfile` and listens on
`XALARM_SYNC_PORT` (default **49732**).

```bash
./update.sh                          # web on 49731, sync on 49732
curl http://localhost:49732/health   # → ok
```

## Public TLS (required for phones outside your LAN)

The app defaults to `wss://xalarm.tinbadger.com/sync`. Add a WebSocket
route on whatever reverse proxy serves xalarm.tinbadger.com:

The relay answers WebSocket upgrades on **both `/ws` and `/sync`**, so a
proxy can forward the path as-is with no rewriting.

**Nginx Proxy Manager** (no new subdomain needed — reuse the existing
xalarm proxy host): edit the host → *Custom Locations* → add:
- Define location: `/sync`
- Scheme `http`, Forward Hostname/IP: your docker host, Forward Port `49732`
- Click the gear icon on that location and paste (the host-level
  *Websockets Support* toggle doesn't reliably apply inside custom
  locations):

```nginx
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_read_timeout 3600s;
```

**Plain nginx:**

```nginx
location /sync {
    proxy_pass http://<docker-host>:49732;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600s;
}
```

**Caddy:**

```
xalarm.tinbadger.com {
    handle /sync {
        reverse_proxy <docker-host>:49732
    }
    # ...existing site config
}
```

LAN-only use works without any proxy: set the app's sync server to
`ws://<server-ip>:49732/ws` in Settings → Time Sync.

## Protocol sketch

JSON over one WebSocket per app (`packages/sync_protocol` is the shared
codec): `hello{name}` → `welcome{code, resumeKey}`; `pairRequest{code}` →
`pairIncoming` → `pairAccept` → `paired` on both sides. Actions carry
absolute **server timestamps** (clients NTP-sync against the server with
ping/pong), which is what keeps both displays drift-free. On any disconnect
the session enters a 5-second limbo (`peerLost`); both sides must send
`resume` before it expires or the session is purged.
