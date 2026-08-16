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
  Connects, hydrates self/device/battery/custom-vars/contacts, drains the
  message queue on `pushMessagesWaiting`, upserts contacts on new adverts.
* `TransportFactory` — mock in the simulator, USB on device.
* Views: Node (identity/radio/position/GPS toggle), Contacts (+ DM composer),
  Messages (+ channel-0 composer), Map (self + contacts).

## Driver

DriverKit dext matching VID 0x2886 / PID 0x1667, CDC-Data interface. Two
external-method selectors (`write`, `startRead`/`stopRead`) shared with
`USBTransport.Selector`. See `docs/entitlement-request.md` — the dext cannot
load on hardware without Apple's USB-transport entitlement.

## GPS note

On GPS-equipped boards (Wio Tracker L1) the companion firmware exposes GPS as
custom var `gps` (`1`/`0`) — `MeshCoreClient.setGPS(enabled:)`. Live position
comes back in self-telemetry (Cayenne LPP), not in `SelfInfo`, which carries the
*advertised* location.

## Versioning

`MARKETING_VERSION` in `project.yml`; `CURRENT_PROJECT_VERSION` =
major×10000 + minor×100 + patch (same scheme as Photoslop).
