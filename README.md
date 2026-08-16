# Cosmic-Crisp-MeshCore

A native iPadOS client for [MeshCore](https://github.com/meshcore-dev/MeshCore) LoRa mesh radios — over **USB**, not Bluetooth.

[![CI](https://github.com/CryptoJones/Cosmic-Crisp-MeshCore/actions/workflows/ci.yml/badge.svg)](https://github.com/CryptoJones/Cosmic-Crisp-MeshCore/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg?logo=apache)](LICENSE)
[![GitHub](https://img.shields.io/badge/GitHub-CryptoJones%2FCosmic--Crisp--MeshCore-181717?logo=github&logoColor=white)](https://github.com/CryptoJones/Cosmic-Crisp-MeshCore)
[![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Version](https://img.shields.io/badge/version-v0.1.0--dev-orange)]()

## Why

The official MeshCore companion apps talk to nodes over Bluetooth LE. That's the
right call for phones, but it means a node flashed with the **USB serial
companion** firmware — the build you want when a computer drives the radio —
is invisible to an iPad. iPadOS 16.1+ on M-series iPads can host
[DriverKit](https://developer.apple.com/documentation/driverkit) USB drivers, so
there's no technical reason an iPad can't be that computer.

Cosmic-Crisp-MeshCore is that app: plug a MeshCore USB-companion node into an
M-series iPad Pro/Air and get contacts, direct messages, channels, a live map, and
node configuration — the same feature set as the official companion, wired.

## Status

**Pre-alpha, under active development.** See [CHANGELOG.md](CHANGELOG.md).

| Piece | State |
|---|---|
| `MeshCoreKit` — companion protocol (framing, commands, response parsing) | scaffolded, unit-tested |
| `MeshCoreUSB` — DriverKit USB CDC-ACM driver extension | scaffolded (needs entitlement to run on device) |
| App — SwiftUI shell, node info, contacts, messaging, map | scaffolded |
| CI — build + test on iPad simulator | wired |

## Requirements

- iPad with an M-series chip (iPad Pro M1 or later, iPad Air M1 or later), iPadOS 17+
- A MeshCore node running the **`companion_radio_usb`** firmware
  (e.g. Seeed Wio Tracker L1: `WioTrackerL1_companion_radio_usb-*.uf2`)
- To build: Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- To run the USB driver on hardware: the `com.apple.developer.driverkit.transport.usb`
  entitlement — see [docs/entitlement-request.md](docs/entitlement-request.md)

## Building

```sh
xcodegen generate
open Cosmic-Crisp-MeshCore.xcodeproj
```

Or from the command line, against the simulator (no entitlements needed —
the app runs with a mock transport there):

```sh
xcodebuild -scheme CosmicCrisp -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4)' test
```

The protocol package builds and tests on any Swift toolchain, including Linux:

```sh
cd Packages/MeshCoreKit && swift test
```

## Layout

```
App/                 SwiftUI app target (CosmicCrisp)
Driver/              DriverKit dext (MeshCoreUSB) — USB CDC-ACM → app
Packages/MeshCoreKit Pure-Swift MeshCore companion protocol + transports
docs/                Architecture notes, entitlement request text
.github/workflows/   CI
```

## Contributing

Branch + PR. **Run `scripts/ci-local.sh` before every push** — it mirrors the
GitHub workflow step for step and must print `ALL CI STEPS PASSED LOCALLY`.
See [AGENTS.md](AGENTS.md). See [docs/architecture.md](docs/architecture.md)
before touching the protocol layer — frame layouts are documented there and
mirror the reference [`meshcore` Python library](https://github.com/meshcore-dev/meshcore_py).

## License

Apache-2.0. See [LICENSE](LICENSE).

Not affiliated with Apple, MeshCore, Seeed Studio, or Washington State University's apple-breeding program.

## Credits

CryptoJones and Fable5.
