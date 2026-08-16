# DriverKit USB entitlement request

The `MeshCoreUSB` driver extension needs the
`com.apple.developer.driverkit.transport.usb` entitlement (plus the base
`com.apple.developer.driverkit`) to run on a real iPad. Apple grants these per
developer account on request. Nothing else in the project is blocked on it: the
protocol package builds anywhere, and the app runs against a mock node in the
simulator.

## Where

Sign in with the team's Apple Developer account and open the DriverKit
entitlement request form. It has historically lived at
<https://developer.apple.com/contact/request/system-extension/> ("Request
DriverKit or System Extension entitlements"). If that URL has moved, it's
reachable from *Account → Program Resources → Additional Resources* or by
searching "DriverKit entitlement request" on developer.apple.com. Choose
**DriverKit** and check the **USB transport** capability.

## What to paste

**App name:** Cosmic-Crisp-MeshCore
**Bundle ID (app):** net.thenetwerk.cosmiccrisp
**Bundle ID (dext):** net.thenetwerk.cosmiccrisp.MeshCoreUSB
**Platform:** iPadOS (M-series iPad)
**Open source:** https://github.com/CryptoJones/Cosmic-Crisp-MeshCore (Apache-2.0)

**Description of the driver and why it's needed:**

> Cosmic-Crisp-MeshCore is an open-source iPadOS client for MeshCore, an
> off-grid LoRa mesh-radio network (github.com/meshcore-dev/MeshCore). MeshCore
> nodes expose a companion API over either Bluetooth LE or a USB CDC-ACM serial
> interface; nodes flashed with the USB-serial companion firmware — the standard
> configuration when a computer drives the radio — have no BLE stack and are
> therefore unreachable from iPadOS today.
>
> The requested DriverKit USB extension is a minimal CDC-ACM bulk-pipe driver
> that matches only MeshCore companion hardware (initially Seeed Studio Wio
> Tracker L1, VID 0x2886 / PID 0x1667) and forwards bytes between the node and
> the containing app through an IOUserClient. It performs no control transfers
> beyond interface open, does not touch other USB devices, and is only active
> while the app is running.
>
> No supported alternative exists: ExternalAccessory requires MFi hardware,
> and the mesh radio cannot be reached over the network (it is off-grid by
> design). The project targets M-series iPad Pro/Air on iPadOS 17+.

**Devices:** Seeed Studio Wio Tracker L1 (VID 0x2886, PID 0x1667). Additional
MeshCore boards may be added later; each will be listed in the entitlement's
device allow-list.

## After approval

1. In Certificates, Identifiers & Profiles, edit the **dext** App ID
   (`net.thenetwerk.cosmiccrisp.MeshCoreUSB`) → enable *DriverKit* + *DriverKit
   USB Transport (VID/PID)*, adding the vendor/product pair.
2. Edit the **app** App ID → enable *DriverKit Communicates with Drivers* and
   *System Extension*.
3. Regenerate the provisioning profiles for both targets; CI reads them from
   the same secrets layout as Photoslop.
4. Set `DEVELOPMENT_TEAM` in `Local.xcconfig` (git-ignored) or via CI env, and
   `xcodegen generate`.
