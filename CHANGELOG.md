# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [Unreleased]

### Added
- Security & profiles (#17): app lock via Face ID / Touch ID / passcode (on launch or
  every foreground with grace period), complete data protection on stored history,
  known-radio profiles keyed by public key with optional per-radio passcode (shared
  iPads), Security & radios screen, forget-radio (deletes its history).
- `CosmicCrispDev` target: same app without the embedded driver so it can be dev-signed
  and installed on a device while the DriverKit entitlement is pending; Connection
  sheet (tap the status bar) to set a TCP radio endpoint (bridge / WiFi companion).
- Diagnostics (#10): per-contact path discovery (out/in hops resolved to contact names),
  trace route with per-hop SNR, packet log (raw packets + RF log lines, hex/ASCII, cap 500,
  toggle/clear) reachable from Node and contact diagnostics.
- Map (#9): type-tinted pins, own node from live GPS fix, tap → contact card (type,
  hops, distance/bearing, last heard, Details / Message), learned-path polylines through
  identifiable hops (highlighted on selection), toggles for paths / flood-only nodes /
  iPad location, Fit all.
- Repeater / room-server admin (#8): login (admin/guest) with reply matching by key
  prefix, logout, status request (full NodeStatus panel), remote CLI console with quick
  commands (replies with text type 1 routed to the console, not the chat), room servers
  open as conversations with signed posts attributed to the original poster.
- Node settings (#7): radio editor with regional presets (freq/BW/SF/CR/TX), position
  picker (map pin / node GPS / iPad location), share-position-in-adverts, GPS receiver,
  zero-hop/flood adverts, manual-approve contacts, multi-ACK, telemetry modes, sensors
  (Cayenne LPP), core/radio/packet statistics, node clock + sync, Bluetooth PIN, reboot.
- Contacts (#6): searchable list with type/distance/bearing/last-heard, detail view
  (route, hops, position, reset path), share as meshcore:// link + QR (own card too),
  import from link, broadcast card to mesh, delete, manual-add flow for adverts heard
  while manual-add-contacts is on. Self position prefers the live GPS fix from telemetry.
- MeshCoreKit protocol coverage (#5): contact export/import/share/add/remove/advert-path,
  remote login/logout/status/telemetry/path-discovery/trace/remote-CLI, node params
  (other params, PIN, tuning, time, radio, TX power, stats), Cayenne LPP decoding,
  status/telemetry/path/trace/login/raw/log response parsing; opcode table audited
  against the reference library. Requests can claim push-coded replies (self telemetry).
- Messaging core: per-conversation chat (channels + direct), persistent history
  (`MessageStore`), DM delivery tracking (messageSent → ACK, RTT shown) with the
  reference retry policy (3 attempts, reset path before the 3rd), unread badges,
  channel management (Public / #hashtag / custom / random keys) via `ChannelsView`,
  contacts open conversations. `LiveRadioTests` (opt-in via `MESHCORE_TCP`) verified a real
  channel broadcast on a Wio Tracker L1.
- `TCPTransport` (Network.framework) + `-tcp host:port` / `MESHCORE_TCP` selection,
  and `tools/serial-bridge.py` so the simulator can drive a real USB radio.
  Verified end-to-end against a Wio Tracker L1.
- USB plumbing: dext bulk IN/OUT data path (endpoint discovery, async reads,
  re-arm, stall recovery, ZLP on writes), user-client async delivery via packed
  scalars, app-side `USBTransport` (IOKit user client + notification port),
  `AsyncScalarCodec` with tests, bridging header, CI device build.
- Project scaffold: XcodeGen project, SwiftUI app shell, DriverKit dext skeleton,
  `MeshCoreKit` protocol package with frame codec + command builders + response
  parser and unit tests, GitHub Actions CI, entitlement-request text.
