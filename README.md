# blackstorm-pump-screen

Show your own images and animated GIFs on the pump LCD of the **Blackstorm Luna Pro+ 360 ARGB** AIO cooler (Verkkokauppa.com's own brand), which ships with no display software.

Plain PowerShell, no drivers and nothing to install. Windows only.

## Does it work with my cooler?

The screen is a USB HID device with ID `1D6B:013B`, made by Byyeetek. Check whether yours is the same:

```powershell
Get-PnpDevice -PresentOnly | Where-Object InstanceId -match 'VID_1D6B&PID_013B'
```

If that prints a device, this should work. It has only been tested on one Luna Pro+ 360; other coolers built around the same Byyeetek screen may work too. Reports either way are welcome.

## Quick start

```powershell
git clone https://github.com/nicknav98/blackstorm-pump-screen
cd blackstorm-pump-screen

# test card for 10 seconds
powershell -ExecutionPolicy Bypass -File .\pumpimg.ps1 -Brightness 80

# an animated GIF, until you press Ctrl+C
powershell -ExecutionPolicy Bypass -File .\pumpimg.ps1 -Image .\media\my.gif -Brightness 80 -Seconds 0
```

If the picture is sideways, add `-Rotate 90` (or `180`, `270`; degrees anticlockwise).

### `pumpimg.ps1` options

| Option | Default | Meaning |
| --- | --- | --- |
| `-Image` | test card | JPG, PNG or GIF. GIFs animate using their own frame timings |
| `-Seconds` | `10` | How long to show it. `0` = until stopped |
| `-Brightness` | unchanged | 0-100. The screen starts at 0 (black), so set this |
| `-Rotate` | `0` | `0`, `90`, `180` or `270` degrees anticlockwise |
| `-Width`, `-Height` | `480` | Size frames are rendered at. The image is cropped to fill |
| `-Quality` | `80` | JPEG quality |
| `-Fps` | `10` | Refresh rate for still images |

## Keep it on permanently

The pump stores nothing: when the stream stops, the screen goes black. To have your GIF up whenever you're logged in:

```powershell
powershell -ExecutionPolicy Bypass -File .\install-autostart.ps1 -Image .\media\my.gif -Rotate 90 -Brightness 100
```

That adds a `Pump Screen` shortcut to your Startup folder which runs `pump-loop.ps1` hidden at logon. The loop reconnects by itself after sleep or a replug.

- Stop it: `.\stop-pump.ps1`
- Remove the autostart: `.\install-autostart.ps1 -Remove`
- Change the image: run `install-autostart.ps1` again with new options, then `stop-pump.ps1` and start the shortcut

Don't move the folder after installing; the shortcut points at it.

## Troubleshooting

- **`pump HID device not found`**: the pump's USB cable isn't plugged into a motherboard USB header, or your screen has a different ID.
- **Screen stays black**: pass `-Brightness 80`.
- **Garbled or flickering picture**: two things are writing to the screen. Run `stop-pump.ps1` before starting anything else.
- **Scripts won't run**: use the `powershell -ExecutionPolicy Bypass -File ...` form shown above.

## How it works

The screen speaks the same protocol as PCCooler's CPS-Display software: text commands in a small framing layer over 1024-byte HID reports, and a realtime mode where the host streams JPEG frames. See [PROTOCOL.md](PROTOCOL.md) for the details, and `tools/` for two helpers for poking at commands by hand (`frame.js` builds a framed request as hex, `hidx.ps1` sends hex and prints the replies).

## Disclaimer

Unofficial, and not affiliated with Blackstorm, Verkkokauppa.com, Byyeetek or PCCooler. It only sends display commands, but you use it at your own risk.

## License

[MIT](LICENSE)
