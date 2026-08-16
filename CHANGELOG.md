# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [Unreleased]

### Added
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
