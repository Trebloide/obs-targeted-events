---
name: obs-targeted-events
description: Create or adapt calls to obs-targeted-events.dll through OBS WebSocket v5 to send DOM events to a specific browser source and implement their reception in HTML. Use for clients, overlays, and automations that need this plugin.
---

# Calling OBS Targeted Events

Generate reusable code in the project's language or client library. The DLL runs
as an OBS plugin and exposes a vendor request through OBS WebSocket v5.
The client uses that WebSocket connection rather than loading the DLL directly.

## 1. Prepare the connection and target

- Reuse the existing OBS WebSocket client when available.
- Obtain the URL, port, and password from the user's configuration. A local
  example is `ws://127.0.0.1:4455`; the port is configurable. Keep the password
  in private configuration or environment variables.
- Wait until v5 identification/authentication completes before sending requests.
  Use the client library's authentication implementation.
- Check that the plugin is loaded: the OBS log should contain
  `[targeted-browser-events] Ready`.
- Obtain the exact **browser source** name, the DOM event name, and the data
  object. Names used in the examples can be replaced.
- The source's page must be loaded and its listener registered. Sources that
  unload their browser when hidden cannot receive events while unloaded.

Creating code does not imply sending events to a live session. Execute calls
when the user's task includes that execution.

## 2. Build the request

Call `CallVendorRequest` with these parameters:

```json
{
  "vendorName": "targeted-browser-events",
  "requestType": "emit_event",
  "requestData": {
    "sourceName": "MyOverlay",
    "eventName": "overlay_event",
    "eventData": {
      "action": "show",
      "text": "Hello"
    }
  }
}
```

Keep `CallVendorRequest`, `targeted-browser-events`, and `emit_event` literal.
Adapt `sourceName`, `eventName`, and `eventData` to the use case. Do not replace
this call with `BroadcastCustomEvent`: this contract targets the named browser.

| Field | Plugin contract |
| --- | --- |
| `sourceName` | Nonempty string, exact name of an existing `browser_source`; maximum 1024 UTF-8 bytes. |
| `eventName` | Nonempty string, identical to the listener's event name; maximum 256 UTF-8 bytes. |
| `eventData` | JSON object; may be omitted, in which case `{}` is used. Do not pass a JSON string, array, `null`, number, or boolean. Maximum 65536 bytes of JSON serialized by OBS. |

Wrap lists or scalar values in an object, for example `{ "items": [...] }` or
`{ "value": 3 }`. Build objects and serialize them using the language's JSON
library; avoid string concatenation or manually escaping JSON.

## 3. Send the request and check the response

Example using `obs-websocket-js` v5 with an already connected `obs` instance:

```js
async function sendOBSEvent(obs, sourceName, eventName, eventData = {}) {
  const response = await obs.call('CallVendorRequest', {
    vendorName: 'targeted-browser-events',
    requestType: 'emit_event',
    requestData: { sourceName, eventName, eventData }
  });

  const result = response.responseData;
  if (result?.ok !== true) {
    throw new Error(result?.error || 'obs-targeted-events response missing ok=true');
  }
  return result;
}

await sendOBSEvent(obs, 'MyOverlay', 'overlay_event', {
  action: 'show',
  text: 'Hello'
});
```

If a new Node.js client is needed, install `obs-websocket-js` v5 in the project
and connect before using the function above. ES module (`.mjs`) example:

```js
import { OBSWebSocket } from 'obs-websocket-js';

const obs = new OBSWebSocket();
await obs.connect(
  process.env.OBS_WEBSOCKET_URL || 'ws://127.0.0.1:4455',
  process.env.OBS_WEBSOCKET_PASSWORD,
  { rpcVersion: 1 }
);
try {
  // Include the sendOBSEvent function defined above.
  await sendOBSEvent(obs, 'MyOverlay', 'overlay_event', { action: 'show' });
} finally {
  await obs.disconnect();
}
```

In a persistent application, retain the connection according to its lifecycle.
Handle connection/authentication failures and exceptions from `obs.call` at the
client's entry point.

### Clients that build WebSocket v5 messages directly

After the authenticated handshake, the equivalent JSON message is:

```json
{
  "op": 6,
  "d": {
    "requestType": "CallVendorRequest",
    "requestId": "targeted-event-001",
    "requestData": {
      "vendorName": "targeted-browser-events",
      "requestType": "emit_event",
      "requestData": {
        "sourceName": "MyOverlay",
        "eventName": "overlay_event",
        "eventData": { "action": "show" }
      }
    }
  }
}
```

Use a unique `requestId` for each request. Match it to the opcode 7 response and
check `d.requestStatus.result` first. In that raw message, the plugin's result is
at `d.responseData.responseData`.
Libraries such as `obs-websocket-js` already remove the protocol envelope: with
`obs.call`, the plugin's result is at `response.responseData`.

A successful plugin response has this shape:

```json
{
  "ok": true,
  "status": "dispatched_no_delivery_ack"
}
```

`ok: true` confirms that the source's procedure was invoked. It does not confirm
that the JavaScript listener ran or that the visual effect appeared.
The plugin provides no queue, retries, or acknowledgment from HTML. After a
timeout, the event may already have been sent; do not automatically repeat an
action with cumulative effects without an application deduplication strategy.

## 4. Receive events in the source's HTML

Register the listener on `window` in the page loaded by the source:

```html
<div id="message"></div>
<script>
  window.addEventListener('overlay_event', (event) => {
    const data = event.detail;
    if (data?.action === 'show') {
      document.getElementById('message').textContent = data.text ?? '';
    }
  });
</script>
```

The event name must match `eventName` exactly. Read the payload from
`event.detail` and apply only the actions supported by the overlay.

The target is the OBS source. Reusing the same source in multiple scenes shares
the browser; create distinct sources for independent targets.

## 5. Diagnose failures and verify when appropriate

Distinguish transport/authentication failures, outer `CallVendorRequest` errors,
and internal plugin errors (`ok: false`, `error`). Outer success alone is
insufficient.

| Error returned by the plugin | What to check |
| --- | --- |
| `sourceName and eventName are required non-empty strings` | Types and values of both fields. |
| `Source or event name is too long` | UTF-8 byte limits. |
| `eventData must be a JSON object` | Send an object without applying `JSON.stringify` to the field first. |
| `eventData exceeds 64 KiB or cannot be serialized` | Reduce the object and review its JSON data. |
| `Source not found` | Exact source name in the current scene collection. |
| `Target is not a browser source` | Type of the selected source. |
| `Browser source does not expose javascript_event` | obs-browser compatibility and loading. |

If the vendor or request is unavailable, check that the DLL loaded and registered
by looking for the `Ready` message in the OBS log.
If `ok: true` is returned but no effect appears, check that the page is loaded,
the listener is registered, the event name matches, and its code interprets the
received object.

When the task includes integration testing, use two distinct browser sources
with counters and listeners for the same event. Send to one and verify that
only its counter changes; repeat with the other target. Report the call result
and observed reception separately.

## References

- Plugin contract: `src/plugin.c` and `LEEME.md` when the repository is available.
  This skill describes `emit_event` in implementation 0.1.0; review those files
  when using a version with API changes.
- [obs-websocket-js client](https://github.com/obs-websocket-community-projects/obs-websocket-js): connection, authentication, and calls.
- [Official OBS WebSocket v5 protocol](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md): envelopes and `CallVendorRequest`.
