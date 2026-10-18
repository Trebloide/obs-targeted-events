# OBS Targeted Events

Native OBS plugin that sends a DOM event to one browser source selected by its
exact name, using OBS WebSocket v5.

## Build and install

On Windows with OBS 32.2.2, CMake, and Visual Studio C++ Build Tools installed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-windows.ps1
```

Close OBS, copy `package/obs-plugins/64bit/obs-targeted-events.dll` to
`obs-plugins/64bit` inside the OBS installation, and reopen OBS. The log should
contain `[targeted-browser-events] Ready`.

The plugin has been compiled in Release x64. Runtime integration testing in OBS
is still pending.

## Use

Send `CallVendorRequest` with vendor `targeted-browser-events`, request type
`emit_event`, and `sourceName`, `eventName`, and `eventData` in the vendor request
data. The target page receives the payload through `event.detail`.

- [Reusable skill and client/HTML examples (English)](SKILL.md)
- [Build, installation, and integration guide (Spanish)](LEEME.md)
- [Request parameters](examples/request.json)
- [Example receiving page](examples/overlay.html)

An `ok: true` response confirms dispatch to the source procedure, without an
acknowledgment from the HTML listener. Independent destinations require distinct
OBS browser sources.

## License

GPL-2.0-or-later. See [LICENSE](LICENSE). The official obs-websocket API header
retains its original copyright and license notice in `vendor/`.
