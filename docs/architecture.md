# Architecture

```
┌────────────────────────── iPad ──────────────────────────┐
│  CosmicCrisp.app (SwiftUI)                                │
│    NodeSession  ── MeshCoreClient ── MeshCoreTransport    │
│         │              (MeshCoreKit)        │             │
│         │                                   ├─ MockTransport (simulator, tests)
│         │                                   └─ USBTransport ── IOUserClient ─┐
│  MeshCoreUSB.dext (DriverKit) ◄──────────────────────────────────────────────┘
│    IOUSBHostInterface (CDC-Data) → bulk IN/OUT pipes                          │
└──────────────────────────────┬────────────────────────────┘
                               │ USB-C
                     MeshCore node (companion_radio_usb)
```

## MeshCoreKit (pure Swift, no Apple-only deps)

* `Framing` / `FrameDecoder` — serial framing: `<` len16 payload out, `>` len16
  payload in. Decoder resyncs past junk and bogus lengths.
* `Command` — opcode byte builders. Every layout is a straight port of the
  reference [`meshcore` Python library](https://github.com/meshcore-dev/meshcore_py);
  when in doubt, that library is the oracle, and the tests pin exact bytes.
* `ResponseParser` → `Response` — decodes node payloads. Unknown codes are
  surfaced as `.unhandled` (never dropped); truncated ones as `.malformed`.
* `MeshCoreClient` — actor. One request in flight at a time (the node is
  single-threaded about it), pushes on a separate `AsyncStream`, contact list
  collection, timeouts.
* `MockTransport` — a scriptable node. Used by tests and by the simulator build.

## App

* `NodeSession` (`@Observable`, main actor) — the one source of UI truth.
  Conversations are keyed by `ConversationKey` (contact pubkey hex | channel
  index); `ChatMessage`s persist through `MessageStore` (JSON per node key).
  Outbound DMs: `sendTextMessage` → `messageSent(expectedAck, timeout)` tracked
  in `DeliveryTracker`; `pushSendConfirmed(ack)` → delivered; timeout →
  retry (attempt 1), reset path + retry (attempt 2), then failed — the
  reference library's `send_msg_with_retry` policy. Sends are serialised
  through a queue because the client is one-request-at-a-time.
  Connects, hydrates self/device/battery/custom-vars/contacts, drains the
  message queue on `pushMessagesWaiting`, upserts contacts on new adverts.
* `TransportFactory` — `-tcp host:port` (or `MESHCORE_TCP`) → `TCPTransport`; else mock in the simulator, USB on device. `tools/serial-bridge.py` exposes a USB radio on the Mac over TCP for simulator development.
* Views: Node (identity/radio/position/GPS toggle), Contacts (+ DM composer),
  Messages (+ channel-0 composer), Map (self + contacts).

## Driver + USB transport

DriverKit dext matching VID 0x2886 / PID 0x1667, CDC-Data interface.

* `Start`: opens the interface, walks the endpoint descriptors for the bulk
  IN/OUT pair (`findBulkPipes`), allocates IO buffers, arms the first bulk-IN
  `AsyncIO`.
* `ReadComplete`: forwards each IN completion to the connected user client and
  re-arms; on error, reports to the app and tries `ClearStall`.
* `WriteBytes`: synchronous bulk-OUT `IO`, chunked to the OUT buffer, with a
  zero-length packet after exact-multiple-of-max-packet payloads.
* User client external methods (`Driver/MeshCoreUSBShared.h`, included by the
  app's bridging header so both sides share the constants):
  `write` (struct input), `startRead` (async — one completion per IN transfer,
  bytes packed into the 16 async scalars: `[count, 8 bytes/word…]`, max 120
  bytes), `stopRead`.
* App side (`USBTransport`): `IOServiceOpen` on `MeshCoreUSBDriver`,
  `IOConnectCallAsyncScalarMethod(startRead)` with an `IONotificationPort` on a
  private queue; `AsyncScalarCodec` unpacks (unit-tested in the simulator);
  `IOConnectCallStructMethod(write)` for sends. IOKit has no Swift module on
  iOS, so `IOKitLib.h` comes in via `App/CosmicCrisp-Bridging-Header.h`.
* iPadOS has **no** in-app driver activation API (`OSSystemExtensionRequest` is
  macOS-only): the embedded dext ships inside the app and the user enables it in
  the Settings app.

Runs on hardware only with Apple's USB-transport entitlement — see
`docs/entitlement-request.md`. CI compiles this path with a generic iOS device
destination so it can't rot while we wait.

## GPS note

On GPS-equipped boards (Wio Tracker L1) the companion firmware exposes GPS as
custom var `gps` (`1`/`0`) — `MeshCoreClient.setGPS(enabled:)`. Live position
comes back in self-telemetry (Cayenne LPP), not in `SelfInfo`, which carries the
*advertised* location.

## Versioning

`MARKETING_VERSION` in `project.yml`; `CURRENT_PROJECT_VERSION` =
major×10000 + minor×100 + patch (same scheme as Photoslop).
