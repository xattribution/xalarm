# xalarm ↔ Home Assistant

xalarm can serve a small token-authenticated REST API on your local network so
Home Assistant can **see and control alarms and schedules** — show the next
alarm on a dashboard, toggle alarms with a switch, or drive automations off
alarm state.

## 1. Turn on the API in the app

Settings (gear icon) → **Home Assistant** → enable **Local API**.

- Note the **port** (default `8787`) and copy the **access token**.
- The base URL is `http://<phone-ip>:8787/api`. Give your phone a static IP /
  DHCP reservation on your router so the address doesn't drift.

> Reality check: the API answers while the app process is alive (foreground or
> background). If Android fully kills the app, the API sleeps until the app is
> next opened — alarms themselves still ring either way, since those are
> scheduled with the OS.

## 2. Endpoints

All requests need the header `Authorization: Bearer <token>`.

| Method | Path | What it does |
|--------|------|--------------|
| GET | `/api/status` | alarm counts + the next alarm (id, label, ISO time) |
| GET | `/api/alarms` | every alarm with rule, bounds, next fire, summary |
| GET | `/api/alarms/{id}` | one alarm |
| POST | `/api/alarms` | create — body is alarm JSON (see below) |
| PUT | `/api/alarms/{id}` | update any subset of fields (merge) |
| DELETE | `/api/alarms/{id}` | delete |
| POST | `/api/alarms/{id}/enable` | switch on |
| POST | `/api/alarms/{id}/disable` | switch off |
| POST | `/api/alarms/{id}/toggle` | flip |
| GET | `/api/schedules` | built-in + custom shift patterns |

Quick test from any machine on the LAN:

```bash
curl -H "Authorization: Bearer TOKEN" http://PHONE_IP:8787/api/status
```

### Alarm JSON (create/update)

```json
{
  "label": "Day shift",
  "enabled": true,
  "snoozeMinutes": 9,
  "vibrate": true,
  "rule": {
    "type": "shiftCycle",
    "anchorDate": "2026-07-13T00:00:00.000",
    "pattern": [true, true, false, false, true, true, true,
                false, false, true, true, false, false, false],
    "times": [{"h": 6, "m": 0}],
    "perDayTimes": {"4": [{"h": 18, "m": 0}]}
  },
  "bounds": {"startDate": null, "end": {"type": "never"}}
}
```

Rule types: `once`, `weekly`, `dailyInterval`, `hourlyInterval`,
`monthlyOrdinal`, `shiftCycle` — the JSON shapes match what
`GET /api/alarms` returns, so the easiest way to learn them is to create an
alarm in the app and read it back.

## 3. Home Assistant configuration

Add to `configuration.yaml` (or split into packages). Replace `PHONE_IP` and
`TOKEN`.

### Next-alarm sensor

```yaml
rest:
  - resource: http://PHONE_IP:8787/api/status
    headers:
      Authorization: "Bearer TOKEN"
    scan_interval: 60
    sensor:
      - name: "xalarm next alarm"
        value_template: >-
          {{ value_json.nextAlarm.at if value_json.nextAlarm else 'none' }}
        json_attributes_path: "$.nextAlarm"
        json_attributes: [id, label, at]
      - name: "xalarm enabled alarms"
        value_template: "{{ value_json.enabledCount }}"
```

### Toggle a specific alarm (switch)

```yaml
rest_command:
  xalarm_enable:
    url: "http://PHONE_IP:8787/api/alarms/{{ id }}/enable"
    method: POST
    headers:
      Authorization: "Bearer TOKEN"
  xalarm_disable:
    url: "http://PHONE_IP:8787/api/alarms/{{ id }}/disable"
    method: POST
    headers:
      Authorization: "Bearer TOKEN"

# One switch per alarm id you care about (alarm ids are shown by /api/alarms):
switch:
  - platform: template
    switches:
      work_alarm:
        friendly_name: "Work alarm"
        turn_on:
          action: rest_command.xalarm_enable
          data: { id: 1 }
        turn_off:
          action: rest_command.xalarm_disable
          data: { id: 1 }
```

### Automation ideas

```yaml
# Warm the lights 20 minutes before the next alarm
automation:
  - alias: "Pre-alarm wakeup lights"
    triggers:
      - trigger: template
        value_template: >-
          {{ states('sensor.xalarm_next_alarm') not in ['none', 'unknown']
             and (as_datetime(states('sensor.xalarm_next_alarm')) - now())
                 < timedelta(minutes=20) }}
    actions:
      - action: light.turn_on
        target: { entity_id: light.bedroom }
        data: { brightness_pct: 30, transition: 300 }
```

## 4. Security notes

- The token is required on every request; regenerate it from settings if it
  ever leaks. Traffic is plain HTTP on your LAN — don't port-forward it to the
  internet.
- The API binds to all interfaces on the phone; your router/firewall defines
  who can reach it.
