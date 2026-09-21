# xalarm Time Sync — server setup

Time Sync lets a group of xalarm apps share one live timer + stopwatch.
Whoever's code the others join becomes the **host**; the host decides
whether members can start/pause/reset/lap or only watch, and can remove
members. Codes are 6 characters, shareable as text or as a QR code the app
can scan (or that the phone's camera app opens as an `xalarm://sync` link).
The relay is a tiny in-memory WebSocket server you self-host next to the
download site.

## What the server stores

Nothing durable, by design:
- Self-chosen display names and 6-char session codes — RAM only.
- The last timer/stopwatch action per session (so a reconnecting or newly
  joining member can catch up) — RAM only.
- A session ends when the host leaves, or when the host's connection is
  gone for longer than the grace window (default 15 s, `GRACE_MS`). A
  member who drops has the same window to come back before being removed;
  the session carries on for everyone else. A server restart wipes all
  sessions.

No accounts, no logs of alarm data, no persistence.

## Abuse limits

The relay is reachable from the internet, so it defends itself:
- registrations are capped (`MAX_CLIENTS`, default 1000), sessions hold at
  most 8 people, and a host can have at most 8 pending join requests;
- each connection gets a token bucket for messages (40 burst, 15/s) and a
  much smaller one for join requests (5 burst, one per 6 s), which makes
  guessing codes impractical (31^6 ≈ 887 million combinations);
- frames over 4 KB and binary frames close the socket, as does a socket
  that never says hello within 15 s;
- display names are stripped of control, format, and bidi characters;
- the root URL no longer reports how many people are connected.

## Deploying

`update.sh` already brings it up — the `sync` service in
`docker-compose.yml` builds from `server/Dockerfile` and listens on
`XALARM_SYNC_PORT` (default **49732**).

```bash
./update.sh                          # web on 49731, sync on 49732
curl http://localhost:49732/health   # → ok
```

Environment (set in `docker-compose.yml` or `XALARM_SYNC_*` variables):

| Variable | Default | Meaning |
|----------|---------|---------|
| `GRACE_MS` | 15000 | reconnect window for a dropped host/member |
| `MAX_CLIENTS` | 1000 | registration cap |

## Public TLS (required for phones outside your LAN)

The app defaults to `wss://xalarm.tinbadger.com/sync` and refuses plain
`ws://` for anything but local addresses. Add a WebSocket route on whatever
reverse proxy serves xalarm.tinbadger.com:

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
`ws://<server-ip>:49732/ws` in Settings → Time Sync (cleartext is accepted
only for private addresses, `localhost`, and `.local` names).

## Protocol sketch

JSON over one WebSocket per app (`packages/sync_protocol` is the shared
codec).

- `hello{name}` → `welcome{code, resumeKey}`.
- `pairRequest{targetCode}` → the target (or, if they are already in a
  session, that session's host) gets `pairIncoming{name, code}` and answers
  `pairAccept{code}` / `pairDecline{code}`. On accept everyone receives
  `sessionState{hostCode, membersCanControl, members[{name, code,
  connected}]}`; the newcomer also gets the last action per category.
- `action{…}` is fanned out as `peerAction{action, serverTime, seq,
  fromCode}` to every other member. Actions carry absolute **server
  timestamps** (clients NTP-sync against the server with ping/pong), which
  is what keeps all displays drift-free. A member's action is refused with
  `error{code: viewOnly}` while the host has controls locked, and with
  `error{code: frozen}` while the host is reconnecting.
- Host only: `setPolicy{membersCanControl}` and `kick{code}`. Every change
  is broadcast as a fresh `sessionState`.
- Disconnects: `peerLost{code, isHost, graceMs}` to the others; the dropped
  side reconnects with `resume{resumeKey}` and gets `restored` + state
  replay. Expiry removes a member (session continues) or ends the session
  (`purged{reason: hostLost}`). `bye` from a member leaves; from the host
  it ends the session (`purged{reason: hostLeft}`). Members who remain
  connected keep their code and can join or host something else.

QR codes and links encode `xalarm://sync?code=ABC234&server=wss://…`;
the `server` part is optional and only `ws`/`wss` URLs are honoured.
