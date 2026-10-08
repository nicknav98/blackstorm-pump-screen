# Pump screen protocol

Notes from reverse-engineering the Blackstorm Luna Pro+ 360 pump LCD. The screen is made by Byyeetek and speaks the same protocol as PCCooler's CPS-Display / CPS DualScreen apps, even though this device's PID is not in those apps' device tables.

## Transport

- USB HID, VID `1D6B`, PID `013B`
- 1024-byte input and output reports, report ID 0 (so 1025 bytes on the wire from Windows, first byte `00`)
- Short payloads are zero-padded to the full report

## Commands

A command is an HTTP-like text request:

```
METHOD cmd 1\r\n
SeqNumber=N\r\n
Date=<unix ms>\r\n
ContentType=json\r\n        (only with a body)
ContentLength=<n>\r\n       (only with a body)
\r\n
{json body}
```

It is wrapped in a frame:

```
5A | len16BE | data | sum8 | 5A
```

- `len16BE` = `data.length + 5`, big-endian
- `sum8` = low byte of (both length bytes + every data byte)
- Between the two `5A` flags, bytes are escaped: `5A` → `5B 01`, `5B` → `5B 02`

Replies look like `1 200` with `AckNumber = SeqNumber + 1`. They often only arrive after the *next* write, so don't block waiting for one.

### Confirmed commands (all reply 200)

| Request | Body | Effect |
| --- | --- | --- |
| `POST conn` | none | Handshake; returns a state JSON (includes current brightness) |
| `POST brightness` | `{"value":0-100}` | Backlight brightness |
| `POST power` | `{"event":"resume"}` | Wakes the panel |
| `POST realtimeDisplay` | `{"enable":true}` | Enters realtime mode (host streams frames) |

`STATE all` is a sysinfo push from host to device, not a query.

## Image frames

In realtime mode each frame is one JPEG, split into 1000-byte blocks. Each block goes in its own report, unframed and unescaped:

```
5C | len16BE | id(1) | count(2 BE) | index(2 BE) | type(1) | 15 zero bytes | jpeg data
```

- `len16BE` = `21 + data.length` (the 21-byte block header plus the JPEG bytes)
- `id` = frame id, incremented per frame (the script cycles 1..250)
- `count` = total blocks in this frame, `index` = this block's number from 0
- `type` = `1` for JPEG

## Working sequence

1. `POST conn`
2. `POST brightness {"value":80}`
3. `POST power {"event":"resume"}`
4. `POST realtimeDisplay {"enable":true}`
5. Stream JPEG frames

## Observations

- The pump scales JPEGs itself: every size tried from 240x240 to 640x480 displayed. The panel is square; its native resolution is unknown.
- A black screen out of the box was simply `brightness: 0` in the `conn` state.
- Nothing persists. When the stream stops, brightness falls back to 0 and the image disappears, so something on the host has to keep streaming.
- Only one process can drive the screen at a time; two writers corrupt each other's frames.

## Not explored

- The CPS apps' file-upload ("transport") mode, which might let an image persist on the pump without a host stream
- Native resolution / aspect
- Other operating systems (the protocol is plain HID, so a hidapi port should be straightforward)
