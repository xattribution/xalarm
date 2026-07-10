# xalarm

A clean, modern alarm & clock app built around **shift-aware alarms** — Panama
(2-2-3) and other rotating schedules that standard clock apps can't express.
Flutter, so one codebase targets Android (primary) and iOS.

## Why

No mainstream alarm app handles rotating / intermittent shift patterns —
4-on/2-off/3-on/3-off, 2-2-3 Panama, DuPont, mixed 8h and 12h shifts. xalarm
adds those alongside everything a normal clock app does, with a calm
black · blue · tan · white design — no neon, no glow, no gradients.

## What it can schedule

The recurrence engine (`packages/recurrence_engine`) expresses:

| Rule | Example |
|------|---------|
| `OneTime` | Ring once, next 7:00 AM |
| `Weekly` | Mon/Wed/Fri at 7:00 (standard alarm) |
| `DailyInterval` | Every 2 days from a start date |
| `HourlyInterval` | Every 12 hours starting a given time |
| `MonthlyOrdinal` | The 3rd Tuesday of each month |
| `ShiftCycle` | Panama, 4-on/2-off, DuPont… (anchor + on/off pattern + shift times) |

Every rule supports **bounds**: an optional start date and an end condition of
*never*, *until a date*, or *after N times* (so "run for a week then stop" is
just a daily rule with `EndsAfterCount(7)`).

## Feasibility notes (read before shipping)

- **Android** alarm delivery is reliable: `AlarmManager` exact alarms +
  `SCHEDULE_EXACT_ALARM` + a full-screen intent (via the `alarm` package).
- **iOS** does **not** allow true third-party background alarms. The app keeps a
  silent audio session alive as the standard workaround, but iOS reliability is
  inherently below Android and below Apple's own Clock. Android is the primary,
  first-class target; iOS is best-effort.

## Architecture

```
packages/recurrence_engine/   Pure-Dart engine (no Flutter, no I/O).
                              The crown jewel — deterministic, exhaustively
                              tested, reusable by a future native iOS port.
lib/
  core/theme/                 Flat Material 3, black/blue/tan/white, tabular figures
  core/time/                  Clock + next-fire formatting
  features/alarm/
    domain/                   Alarm model, human-readable summaries
    data/                     JSON-file store (no native DB needed for v1)
    application/              Riverpod controllers
    presentation/             Alarm list, add/edit editor, full-screen ring
  features/clock|stopwatch|timer   Tabs (clock is live; others land next)
  features/schedules/         Shift-pattern reference library (drawer)
  features/settings/          Theme selection (drawer)
  services/                   AlarmScheduler, permissions
```

The engine emits the next *K* occurrences of a rule; `AlarmScheduler`
materialises those into native alarms (one per occurrence) and tops the horizon
back up when an alarm rings or the app relaunches.

## Running

Requires the Flutter SDK and, for Android, the Android SDK.

```bash
flutter pub get
flutter run                 # on an Android device/emulator

# Tests
dart test packages/recurrence_engine     # the engine (fast, no Flutter)
flutter test                              # app widget tests
flutter analyze
```

The engine tests are timezone-sensitive by design — run them under a DST zone to
exercise the wall-clock-stability guarantee:

```bash
cd packages/recurrence_engine && TZ=America/New_York dart test
```

## Self-hosting the APK (local-network test loop)

A Linux server with Docker (+ Compose v2) and git can build and serve the APK
with one command — Flutter/JDK/Android SDK all live inside the build image:

```bash
./update.sh                        # pull latest source → build APK in Docker → serve
XALARM_WEB_PORT=50000 ./update.sh  # custom port (default 49731)
```

Then open `http://<server-ip>:49731` from any device on the LAN and download
`xalarm.apk`. See `update.sh` for all `XALARM_*` overrides.

## Time Sync (watch-party timer & stopwatch)

Pair two phones with jackbox-style codes and share a live timer + stopwatch —
either side can start/stop and both screens stay in lockstep via a tiny
self-hosted relay (the `sync` service in docker-compose; in-memory only,
nothing persisted). Pairing is mutual and explicit, a "Synced with <name>"
banner shows while connected, and a dropped session must be reconnected by
both sides within 5 seconds or it's purged. Setup:
[docs/sync_server.md](docs/sync_server.md).

## Home Assistant

The app can serve a token-authenticated REST API on your LAN so Home Assistant
can read and control alarms and schedules (next-alarm sensors, toggle
switches, pre-alarm automations). Enable it in Settings → Home Assistant, then
follow [docs/home_assistant.md](docs/home_assistant.md).

## Status

**Done:** recurrence engine (per-day start-time overrides included), full
Alarm tab, custom shift-schedule builder with saved patterns, World Clock
(multi-timezone compare), Stopwatch with laps, Timer that rings through the
native alarm layer, persisted settings/theme, the Home Assistant local API,
and per-alarm sounds (system default, bundled tones, your own files, or a
one-time URL download) with hold-to-choose snooze durations. Engine has 32
passing unit tests across three time zones.

**Next:** iOS reliability polish, backup/export of schedules.
