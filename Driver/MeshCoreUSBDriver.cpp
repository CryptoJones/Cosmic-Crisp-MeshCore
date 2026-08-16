// MeshCoreUSBDriver.cpp — DriverKit dext for MeshCore USB companion nodes.
//
// STATUS: skeleton. Structure follows Apple's USBDriverKit sample; the pieces
// marked TODO are the bulk-pipe plumbing that can only be exercised on hardware
// once the com.apple.developer.driverkit.transport.usb entitlement is granted.

#include <os/log.h>
#include <DriverKit/IOUserServer.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <USBDriverKit/IOUSBHostInterface.h>
#include <USBDriverKit/IOUSBHostPipe.h>
#include "MeshCoreUSBDriver.h"
#include "MeshCoreUSBUserClient.h"

#define LOG(fmt, ...) os_log(OS_LOG_DEFAULT, "MeshCoreUSB: " fmt "\n", ##__VA_ARGS__)

struct MeshCoreUSBDriver_IVars {
    IOUSBHostInterface *interface = nullptr;
    IOUSBHostPipe *inPipe = nullptr;
    IOUSBHostPipe *outPipe = nullptr;
    IOBufferMemoryDescriptor *inBuffer = nullptr;
    OSAction *readAction = nullptr;       // our own completion action
    OSAction *appAction = nullptr;        // app-supplied async target
    uint16_t inMaxPacket = 64;
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

kern_return_t IMPL(MeshCoreUSBDriver, Start)
{
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) return ret;

    ivars->interface = OSDynamicCast(IOUSBHostInterface, provider);
    if (!ivars->interface) { LOG("provider is not IOUSBHostInterface"); return kIOReturnNoDevice; }

    ret = ivars->interface->Open(this, 0, nullptr);
    if (ret != kIOReturnSuccess) { LOG("Open failed %x", ret); return ret; }

    // TODO: walk the interface descriptor for the bulk IN/OUT endpoints of the
    // CDC-Data interface, CopyPipe() each, allocate inBuffer (inMaxPacket), create
    // readAction via CreateActionReadComplete, and kick the first AsyncIO read.

    RegisterService();
    LOG("started");
    return kIOReturnSuccess;
}

kern_return_t IMPL(MeshCoreUSBDriver, Stop)
{
    OSSafeReleaseNULL(ivars->readAction);
    OSSafeReleaseNULL(ivars->appAction);
    OSSafeReleaseNULL(ivars->inBuffer);
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
    if (!ivars->outPipe) return kIOReturnNotReady;
    // TODO: copy into an IOBufferMemoryDescriptor and outPipe->IO(...) synchronously.
    (void)bytes; (void)length;
    return kIOReturnUnsupported;
}

kern_return_t MeshCoreUSBDriver::SetReadTarget(OSAction *action)
{
    OSSafeReleaseNULL(ivars->appAction);
    ivars->appAction = action;
    if (action) action->retain();
    return kIOReturnSuccess;
}

void IMPL(MeshCoreUSBDriver, ReadComplete)
{
    if (status == kIOReturnSuccess && actualByteCount > 0 && ivars->appAction) {
        // TODO: forward inBuffer[0..actualByteCount) to the user client's DeliverBytes.
    }
    // TODO: re-arm: ivars->inPipe->AsyncIO(ivars->inBuffer, ivars->inMaxPacket, ivars->readAction, 0);
}
