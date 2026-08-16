// MeshCoreUSBDriver.cpp — DriverKit dext for MeshCore USB companion nodes.
//
// Data path:
//   app  --IOConnectCallStructMethod(write)-->  user client --> WriteBytes --> bulk OUT (sync IO)
//   bulk IN (AsyncIO, re-armed after each completion) --> ReadComplete --> user client
//        --> AsyncCompletion(async scalars) --> app
//
// The bulk-pipe code cannot run without the com.apple.developer.driverkit.transport.usb
// entitlement (see docs/entitlement-request.md); it compiles and links against the SDK.

#include <os/log.h>
#include <DriverKit/IOUserServer.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <DriverKit/OSAction.h>
#include <USBDriverKit/IOUSBHostInterface.h>
#include <USBDriverKit/IOUSBHostPipe.h>
#include <USBDriverKit/AppleUSBDefinitions.h>
#include <USBDriverKit/AppleUSBDescriptorParsing.h>
#include <USBDriverKit/USBDriverKitDefs.h>
#include <USBDriverKit/IOUSBHostFamilyDefinitions.h>
#include "MeshCoreUSBDriver.h"
#include "MeshCoreUSBUserClient.h"
#include "MeshCoreUSBShared.h"

#define LOG(fmt, ...) os_log(OS_LOG_DEFAULT, "MeshCoreUSB: " fmt "\n", ##__VA_ARGS__)

static const uint32_t kOutTimeoutMs = 1000;

struct MeshCoreUSBDriver_IVars {
    IOUSBHostInterface *interface = nullptr;
    IOUSBHostPipe *inPipe = nullptr;
    IOUSBHostPipe *outPipe = nullptr;
    IOBufferMemoryDescriptor *inBuffer = nullptr;
    IOBufferMemoryDescriptor *outBuffer = nullptr;
    OSAction *readAction = nullptr;            // our own bulk-IN completion action
    MeshCoreUSBUserClient *client = nullptr;   // current app connection (unretained; cleared on close)
    OSAction *appAction = nullptr;             // app-supplied async completion (retained)
    uint16_t inMaxPacket = 64;
    uint16_t outMaxPacket = 64;
    bool reading = false;
    bool stopping = false;
};

bool MeshCoreUSBDriver::init()
{
    if (!super::init()) return false;
    ivars = IONewZero(MeshCoreUSBDriver_IVars, 1);
    return ivars != nullptr;
}

void MeshCoreUSBDriver::free()
{
    IOSafeDeleteNULL(ivars, MeshCoreUSBDriver_IVars, 1);
    super::free();
}

static kern_return_t findBulkPipes(IOUSBHostInterface *interface, MeshCoreUSBDriver_IVars *iv)
{
    const IOUSBConfigurationDescriptor *config = interface->CopyConfigurationDescriptor();
    if (!config) return kIOReturnNoResources;
    const IOUSBInterfaceDescriptor *ifDesc = interface->GetInterfaceDescriptor(config);
    if (!ifDesc) { IOUSBHostFreeDescriptor(config); return kIOReturnNotFound; }

    // nRF52840 is a full-speed device; max packet math only needs to be right for that.
    const uint32_t speed = kIOUSBHostConnectionSpeedFull;
    kern_return_t ret = kIOReturnNotFound;
    const IOUSBEndpointDescriptor *ep = nullptr;
    while ((ep = IOUSBGetNextEndpointDescriptor(config, ifDesc, (const IOUSBDescriptorHeader *)ep)) != nullptr) {
        if (IOUSBGetEndpointType(ep) != kIOUSBEndpointTypeBulk) continue;
        const uint8_t addr = IOUSBGetEndpointAddress(ep);
        IOUSBHostPipe *pipe = nullptr;
        if (interface->CopyPipe(addr, &pipe) != kIOReturnSuccess || !pipe) continue;
        if (IOUSBGetEndpointDirection(ep) == kIOUSBEndpointDirectionIn) {
            OSSafeReleaseNULL(iv->inPipe);
            iv->inPipe = pipe;
            iv->inMaxPacket = IOUSBGetEndpointMaxPacketSize(speed, ep);
        } else {
            OSSafeReleaseNULL(iv->outPipe);
            iv->outPipe = pipe;
            iv->outMaxPacket = IOUSBGetEndpointMaxPacketSize(speed, ep);
        }
    }
    IOUSBHostFreeDescriptor(config);
    if (iv->inPipe && iv->outPipe) ret = kIOReturnSuccess;
    return ret;
}

kern_return_t IMPL(MeshCoreUSBDriver, Start)
{
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) return ret;

    ivars->interface = OSDynamicCast(IOUSBHostInterface, provider);
    if (!ivars->interface) { LOG("provider is not IOUSBHostInterface"); return kIOReturnNoDevice; }

    ret = ivars->interface->Open(this, 0, nullptr);
    if (ret != kIOReturnSuccess) { LOG("Open failed %x", ret); return ret; }

    ret = findBulkPipes(ivars->interface, ivars);
    if (ret != kIOReturnSuccess) { LOG("no bulk IN/OUT pair on interface: %x", ret); goto fail; }

    ret = ivars->interface->CreateIOBuffer(kIOMemoryDirectionIn, ivars->inMaxPacket, &ivars->inBuffer);
    if (ret != kIOReturnSuccess) { LOG("CreateIOBuffer(in) failed %x", ret); goto fail; }
    ret = ivars->interface->CreateIOBuffer(kIOMemoryDirectionOut, 512, &ivars->outBuffer);
    if (ret != kIOReturnSuccess) { LOG("CreateIOBuffer(out) failed %x", ret); goto fail; }

    ret = CreateActionReadComplete(0, &ivars->readAction);
    if (ret != kIOReturnSuccess) { LOG("CreateActionReadComplete failed %x", ret); goto fail; }

    ret = ivars->inPipe->AsyncIO(ivars->inBuffer, ivars->inMaxPacket, ivars->readAction, 0);
    if (ret != kIOReturnSuccess) { LOG("initial AsyncIO failed %x", ret); goto fail; }
    ivars->reading = true;

    RegisterService();
    LOG("started (in mps %u, out mps %u)", ivars->inMaxPacket, ivars->outMaxPacket);
    return kIOReturnSuccess;

fail:
    OSSafeReleaseNULL(ivars->readAction);
    OSSafeReleaseNULL(ivars->inBuffer);
    OSSafeReleaseNULL(ivars->outBuffer);
    OSSafeReleaseNULL(ivars->inPipe);
    OSSafeReleaseNULL(ivars->outPipe);
    ivars->interface->Close(this, 0);
    ivars->interface = nullptr;
    return ret;
}

kern_return_t IMPL(MeshCoreUSBDriver, Stop)
{
    ivars->stopping = true;
    if (ivars->inPipe) ivars->inPipe->Abort(kIOUSBAbortSynchronous, kIOReturnAborted, nullptr);
    if (ivars->outPipe) ivars->outPipe->Abort(kIOUSBAbortSynchronous, kIOReturnAborted, nullptr);
    if (ivars->appAction && ivars->client) ivars->client->DeliverError(ivars->appAction, kIOReturnNotAttached);
    OSSafeReleaseNULL(ivars->appAction);
    ivars->client = nullptr;
    OSSafeReleaseNULL(ivars->readAction);
    OSSafeReleaseNULL(ivars->inBuffer);
    OSSafeReleaseNULL(ivars->outBuffer);
    OSSafeReleaseNULL(ivars->inPipe);
    OSSafeReleaseNULL(ivars->outPipe);
    if (ivars->interface) { ivars->interface->Close(this, 0); ivars->interface = nullptr; }
    return Stop(provider, SUPERDISPATCH);
}

kern_return_t IMPL(MeshCoreUSBDriver, NewUserClient)
{
    IOService *client = nullptr;
    kern_return_t ret = Create(this, "UserClientProperties", &client);
    if (ret != kIOReturnSuccess) return ret;
    *userClient = OSDynamicCast(IOUserClient, client);
    if (!*userClient) { client->release(); return kIOReturnError; }
    return kIOReturnSuccess;
}

kern_return_t MeshCoreUSBDriver::WriteBytes(const void *bytes, size_t length)
{
    if (!ivars->outPipe || !ivars->outBuffer) return kIOReturnNotReady;
    if (length == 0) return kIOReturnSuccess;

    IOAddressSegment seg = {};
    kern_return_t ret = ivars->outBuffer->GetAddressRange(&seg);
    if (ret != kIOReturnSuccess) return ret;

    const uint8_t *src = static_cast<const uint8_t *>(bytes);
    size_t offset = 0;
    while (offset < length) {
        const uint32_t chunk = (uint32_t)((length - offset) < seg.length ? (length - offset) : seg.length);
        memcpy(reinterpret_cast<void *>(seg.address), src + offset, chunk);
        uint32_t transferred = 0;
        ret = ivars->outPipe->IO(ivars->outBuffer, chunk, &transferred, kOutTimeoutMs);
        if (ret != kIOReturnSuccess) { LOG("bulk OUT failed %x", ret); return ret; }
        offset += transferred ? transferred : chunk;
    }
    // A payload that is an exact multiple of the max packet size needs a zero-length
    // packet so the CDC peer sees the end of the transfer.
    if (length % ivars->outMaxPacket == 0) {
        uint32_t transferred = 0;
        ivars->outPipe->IO(ivars->outBuffer, 0, &transferred, kOutTimeoutMs);
    }
    return kIOReturnSuccess;
}

kern_return_t MeshCoreUSBDriver::SetReadTarget(MeshCoreUSBUserClient *client, OSAction *action)
{
    OSSafeReleaseNULL(ivars->appAction);
    ivars->client = action ? client : nullptr;
    ivars->appAction = action;
    if (action) action->retain();
    return kIOReturnSuccess;
}

void MeshCoreUSBDriver::ClientClosed(MeshCoreUSBUserClient *client)
{
    if (ivars->client == client) {
        OSSafeReleaseNULL(ivars->appAction);
        ivars->client = nullptr;
    }
}

void IMPL(MeshCoreUSBDriver, ReadComplete)
{
    if (ivars->stopping) return;

    if (status == kIOReturnSuccess) {
        if (actualByteCount > 0 && ivars->appAction && ivars->client && ivars->inBuffer) {
            IOAddressSegment seg = {};
            if (ivars->inBuffer->GetAddressRange(&seg) == kIOReturnSuccess) {
                const uint8_t *data = reinterpret_cast<const uint8_t *>(seg.address);
                // A single completion is at most one max-packet (<= 64 on full speed), which
                // fits in one async callback; chunk defensively anyway.
                for (uint32_t off = 0; off < actualByteCount; off += kMeshCoreUSBMaxChunk) {
                    const uint32_t n = (actualByteCount - off) < kMeshCoreUSBMaxChunk
                                     ? (actualByteCount - off) : kMeshCoreUSBMaxChunk;
                    ivars->client->DeliverBytes(ivars->appAction, data + off, n);
                }
            }
        }
    } else if (status == kIOReturnAborted) {
        return;   // Stop() in progress
    } else {
        LOG("bulk IN error %x", status);
        if (ivars->appAction && ivars->client) ivars->client->DeliverError(ivars->appAction, status);
        // Try to recover from a stall; if that fails, give up on the pipe.
        if (ivars->inPipe->ClearStall(false) != kIOReturnSuccess) { ivars->reading = false; return; }
    }

    // Re-arm.
    kern_return_t ret = ivars->inPipe->AsyncIO(ivars->inBuffer, ivars->inMaxPacket, ivars->readAction, 0);
    if (ret != kIOReturnSuccess) { LOG("re-arm AsyncIO failed %x", ret); ivars->reading = false; }
}
