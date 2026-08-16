// MeshCoreUSBShared.h — wire contract between the app (USBTransport.swift) and the dext.
// Keep in sync with `USBTransport.Selector` / `USBTransport.Wire` on the Swift side.

#ifndef MeshCoreUSBShared_h
#define MeshCoreUSBShared_h

#include <stdint.h>

// External method selectors.
enum : uint64_t {
    kMeshCoreUSBSelWrite = 0,      // struct input: raw bytes to send to the node
    kMeshCoreUSBSelStartRead = 1,  // async: register completion; fired once per USB IN completion
    kMeshCoreUSBSelStopRead = 2,   // clear the registered completion
};

// Async completion payload: asyncData[0] = byte count (<= kMeshCoreUSBMaxChunk),
// asyncData[1..] = bytes packed 8 per uint64, little-endian.
// 16 scalars total → 1 length + 15 data words = 120 bytes/callback max.
enum : uint32_t {
    kMeshCoreUSBMaxChunk = 120,
};

#endif
