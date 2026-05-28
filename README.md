# control4-roomcontrol-webhook

Control4 DriverWorks webhook suite with one root HTTP server driver and one linked per-room child driver.

## Packages

`build.sh` produces two `.c4z` files:

- `room_control_webhook.c4z` — root driver; owns HTTP server, auth, client limits, and request routing.
- `room_control_webhook_room.c4z` — room child driver; add one per controllable room and configure that room's presets/custom buttons there.

Root-level `index.html` is local dev/test tooling and is not packaged. Packaged driver documentation lives under `www/`.

## Setup

1. Build both packages or download the release artifacts.
2. Copy both `.c4z` files to ComposerPro's driver folder.
3. Add **Room Control Webhook** once to the project.
4. Add **Room Control Webhook Room** to each room that should accept webhook control.
5. In ComposerPro connections, connect each room child driver's **Root Webhook Link** to an available root **Room Link N** control connection.
6. Configure each room child:
   - **Accept Control**: turn that room on/off for webhook routing.
   - **Preset N Name / Source**: room-specific source presets.
   - **Button N Name**: dynamic `BUTTON_LINK` custom buttons for regular Control4 programming/actions.
7. On the root driver, set **HTTP Port**, optional **Password**, **Allowed Client IPs**, and other server settings.
8. Use the root **Refresh Linked Rooms** action if a child was linked before both drivers finished late init.

## Endpoints

All endpoints return JSON. All except `/health` require authentication when a root password is set.

| Endpoint | Description |
|---|---|
| `GET /health` | Unauthenticated health check |
| `GET /rooms` | Linked room child drivers and enabled state |
| `GET /commands` | Available room-control commands |
| `GET /presets` | Presets reported by linked room drivers |
| `GET /buttons` | Custom buttons reported by linked room drivers |
| `GET\|POST /command` | Send a room command (`room`, `command`, optional `action`, optional `params`) |
| `GET\|POST /preset` | Run a room source preset by name or index |
| `GET\|POST /button` | Trigger a room custom button by name or index |

The `room` parameter accepts a numeric room ID, a room name, a comma-separated list, or `all`. If exactly one linked room is enabled, `room` may be omitted.

Preset configuration is intentionally not saved through the root HTTP API anymore; configure presets on the room child driver.

## Authentication

If **Password** is set on the root driver, send it using any of these:

- `Authorization: Bearer <password>`
- HTTP Basic auth; the password field must match
- `X-Control4-Password: <password>`
- `X-API-Key: <password>`
- `password=<password>` query/form/JSON field

## Example requests

```bash
# Health check
curl http://CONTROLLER_IP:5080/health

# List linked rooms
curl -H 'Authorization: Bearer YOUR_PASSWORD' http://CONTROLLER_IP:5080/rooms

# Send a standard room command
curl -X POST http://CONTROLLER_IP:5080/command \
  -H 'Authorization: Bearer YOUR_PASSWORD' \
  -H 'Content-Type: application/json' \
  -d '{"room":123,"command":"PLAYPAUSE"}'

# Run source preset 1 in a linked room
curl 'http://CONTROLLER_IP:5080/preset?room=123&preset=1&password=YOUR_PASSWORD'

# Trigger custom room button named Party
curl 'http://CONTROLLER_IP:5080/button?room=123&button=Party&action=tap&password=YOUR_PASSWORD'

# Turn off all enabled linked rooms
curl 'http://CONTROLLER_IP:5080/command?room=all&command=ROOM_OFF&password=YOUR_PASSWORD'
```

## Packaging

```bash
./build.sh
```

The script concatenates:

- `src/*.lua` → `driver.lua`
- `room_src/*.lua` → `room_driver/driver.lua`

Then it packages both root and room child `.c4z` files with Snap One `driverpackager`.
