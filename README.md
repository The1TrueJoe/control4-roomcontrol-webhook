# control4-roomcontrol-webhook

Lightweight Control4 DriverWorks driver that exposes a local HTTP service so third-party remotes, scripts, and automation tools can send room-control commands to Director. Button-style actions are handled through the same `/command` endpoint.

## Files

- `driver.xml` — Control4 driver definition and Composer properties.
- `src/` — Lua source modules (concatenated into `driver.lua` at build time).
- `www/` — Packaged web UI and documentation included in the `.c4z`.
- `room_control_webhook.c4zproj` — manifest for [snap-one/drivers-driverpackager](https://github.com/snap-one/drivers-driverpackager).

## Setup

1. Build the `.c4z` (see [Packaging](#packaging) below) or download a release artifact.
2. Copy it to the `Documents\Control4\Drivers` folder on the ComposerPro PC.
3. In ComposerPro → **System Design**, search for **Room Control Webhook** and drag it into any room.
4. On the **Properties** tab, set **Control Rooms** and optionally a **Password**.
5. Use **Preset Config Room** to choose which selected room you are configuring, then set **Preset Source 1** through **Preset Source 5** from the room-specific source dropdowns.
6. Note the read-only **Endpoint** property — it shows the full base URL once the driver starts.

## Endpoints

All endpoints return JSON. All except `/health` require authentication when a password is set.

| Endpoint | Description |
|---|---|
| `GET /health` | Unauthenticated health check |
| `GET /rooms` | List rooms and which are enabled for control |
| `GET /commands` | List all available unified commands |
| `GET /presets` | List saved per-room source presets and available sources |
| `POST /presets` | Save source presets for a room |
| `GET\|POST /command` | Send a command (`room`, `command`, optional `action`, optional `params`) |
| `GET\|POST /preset` | Run a saved source preset by name or index |

The `room` parameter accepts a numeric ID, a room name, a comma-separated list, or `all`.

## Authentication

If **Password** is set, send it using any of these:

- `Authorization: Bearer <password>`
- HTTP Basic auth; the password field must match
- `X-Control4-Password: <password>`
- `X-API-Key: <password>`
- `password=<password>` query/form/JSON field

## Example requests

```bash
# Health check
curl http://CONTROLLER_IP:5080/health

# List rooms
curl -H 'Authorization: Bearer YOUR_PASSWORD' http://CONTROLLER_IP:5080/rooms

# Send a command
curl -X POST http://CONTROLLER_IP:5080/command \
  -H 'Authorization: Bearer YOUR_PASSWORD' \
  -H 'Content-Type: application/json' \
  -d '{"room": 123, "command": "PLAYPAUSE"}'

# Hold volume up, then release
curl 'http://CONTROLLER_IP:5080/command?room=123&command=VOLUME_UP&action=press&password=YOUR_PASSWORD'
curl 'http://CONTROLLER_IP:5080/command?room=123&command=VOLUME_UP&action=release&password=YOUR_PASSWORD'

# Save and run a source preset
curl -X POST http://CONTROLLER_IP:5080/presets \
  -H 'Authorization: Bearer YOUR_PASSWORD' \
  -H 'Content-Type: application/json' \
  -d '{"room":123,"presets":[{"name":"Movie","source":456,"source_type":"watch"}]}'
curl 'http://CONTROLLER_IP:5080/preset?room=123&preset=Movie&password=YOUR_PASSWORD'

# Turn off all selected rooms
curl 'http://CONTROLLER_IP:5080/command?room=all&command=ROOM_OFF&password=YOUR_PASSWORD'
```

## Web UI

Open `www/index.html` from the driver package directly in any browser on your PC. Enter the controller IP, port, and password, then browse rooms, send commands, and run source presets. Source presets are configured in Composer under the driver's **Properties** tab.

