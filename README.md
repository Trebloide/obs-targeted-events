# OBS Targeted Events

Native OBS plugin that sends a DOM event to one browser source selected by its
exact name, using OBS WebSocket v5.

## Reusable AI skill

This repository includes an English-language [SKILL.md](SKILL.md) for AI coding
assistants building integrations with OBS Targeted Events. It covers WebSocket
connection and authentication, `emit_event` requests, HTML event listeners,
payload limits, response handling, and troubleshooting.

Provide the file to your coding assistant as reusable instructions when creating
a client or overlay. It includes examples for both sending events and receiving
their data through `event.detail` in the browser source's HTML.

## Compatibility

- Minimum runtime: **OBS Studio 29.1.0**, with obs-browser and obs-websocket 5.2
  or later loaded. The distributed DLL is for Windows x64.
- Built against the OBS **29.1.0** headers and import library. CMake and a source
  guard reject newer SDKs so a rebuild cannot silently raise the minimum version.
- DLL loading, import resolution, and module exports have been checked against
  OBS **29.1.0** and **32.2.2**. Browser event delivery still needs an integration
  test in OBS.

OBS 29.1.0 is the first stable release whose obs-browser includes the per-source
`javascript_event` procedure. See the [upstream change](https://github.com/obsproject/obs-browser/commit/501f624e0eabe851358bcc34dca785bbf52ac1c9)
and the [browser revision shipped with OBS 29.1.0](https://github.com/obsproject/obs-studio/tree/29.1.0/plugins/obs-browser).

## Build and install

On Windows with CMake >= 3.24 and Visual Studio C++ Build Tools (2019 16.11 or
newer), run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-windows.ps1
```

The script downloads the official OBS 29.1.0 sources and Windows portable
package into `.deps`, verifies their SHA-256 hashes, and builds in Release x64.
It also verifies the pinned obs-websocket 5.2 API header. The portable package is
used for linking and is never installed or launched; your installed OBS can be
newer. An installed OBS is not required to build.

Use `-CMakePath` to select another CMake executable. To use an already extracted
OBS 29.1.0 x64 package instead of downloading the runtime, pass `-OBSInstallDir`
with that package's root. This parameter selects the **build baseline**, not the
OBS installation where the finished plugin will run.

Close OBS, copy `package/obs-plugins/64bit/obs-targeted-events.dll` to
`obs-plugins/64bit` inside the OBS installation, and reopen OBS. The log should
contain `[targeted-browser-events] Ready`.

When upgrading from the previous build, replace its DLL with this one.

## Check binary compatibility

With a 64-bit Python interpreter, run these in separate processes:

```powershell
python scripts/check-windows-compatibility.py .deps/obs-runtime-29.1.0 package/obs-plugins/64bit/obs-targeted-events.dll
python scripts/check-windows-compatibility.py "C:\Program Files\obs-studio" package/obs-plugins/64bit/obs-targeted-events.dll
```

These checks load the DLL and confirm that its module API is 29.1.0 and that its
dependencies and module exports resolve. They do not initialize OBS or test DOM
event delivery. Follow the integration procedure in [LEEME.md](LEEME.md) for that.

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
