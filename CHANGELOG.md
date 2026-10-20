# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [Unreleased]

### Changed
- Apple assigned the *DriverKit USB Transport - VendorID* entitlement to the
  project's developer account on 2026-10-20 (vendor 0x2886, Seeed Studio). The
  dext entitlement now lists `idVendor` only, matching the vendor-scoped grant;
  the driver personality still matches PID 0x1667. Docs updated; the driver has
  not yet been run on hardware.

### Added
- Project scaffold: XcodeGen project, SwiftUI app shell, DriverKit dext skeleton,
  `MeshCoreKit` protocol package with frame codec + command builders + response
  parser and unit tests, GitHub Actions CI, entitlement-request text.
