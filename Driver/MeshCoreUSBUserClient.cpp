// MeshCoreUSBUserClient.cpp — bridges IOConnectCall* from the app to the driver.

#include <os/log.h>
#include <string.h>
#include <DriverKit/IOUserServer.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/OSAction.h>
#include <DriverKit/OSData.h>
#include "MeshCoreUSBDriver.h"
#include "MeshCoreUSBUserClient.h"
#include "MeshCoreUSBShared.h"

#define LOG(fmt, ...) os_log(OS_LOG_DEFAULT, "MeshCoreUSB.UC: " fmt "\n", ##__VA_ARGS__)

struct MeshCoreUSBUserClient_IVars {
    MeshCoreUSBDriver *driver = nullptr;
};

bool MeshCoreUSBUserClient::init()
{
    if (!super::init()) return false;
    ivars = IONewZero(MeshCoreUSBUserClient_IVars, 1);
    return ivars != nullptr;
}

void MeshCoreUSBUserClient::free()
{
    IOSafeDeleteNULL(ivars, MeshCoreUSBUserClient_IVars, 1);
    super::free();
}

kern_return_t IMPL(MeshCoreUSBUserClient, Start)
{
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) return ret;
    ivars->driver = OSDynamicCast(MeshCoreUSBDriver, provider);
    return ivars->driver ? kIOReturnSuccess : kIOReturnNoDevice;
}

kern_return_t IMPL(MeshCoreUSBUserClient, Stop)
{
    if (ivars->driver) ivars->driver->ClientClosed(this);
    return Stop(provider, SUPERDISPATCH);
}

kern_return_t MeshCoreUSBUserClient::ExternalMethod(uint64_t selector, IOUserClientMethodArguments *arguments,
                                                    const IOUserClientMethodDispatch *dispatch, OSObject *target,
                                                    void *reference)
{
    if (!ivars->driver) return kIOReturnNotAttached;
    switch (selector) {
    case kMeshCoreUSBSelWrite: {
        if (!arguments->structureInput) return kIOReturnBadArgument;
        return ivars->driver->WriteBytes(arguments->structureInput->getBytesNoCopy(),
                                         arguments->structureInput->getLength());
    }
    case kMeshCoreUSBSelStartRead:
        if (!arguments->completion) return kIOReturnBadArgument;
        return ivars->driver->SetReadTarget(this, arguments->completion);
    case kMeshCoreUSBSelStopRead:
        return ivars->driver->SetReadTarget(this, nullptr);
    default:
        return super::ExternalMethod(selector, arguments, dispatch, target, reference);
    }
}

void MeshCoreUSBUserClient::DeliverBytes(OSAction *action, const uint8_t *bytes, size_t length)
{
    if (length > kMeshCoreUSBMaxChunk) length = kMeshCoreUSBMaxChunk;
    IOUserClientAsyncArgumentsArray args = {};
    args[0] = length;
    // Pack bytes little-endian, 8 per scalar, starting at args[1].
    memcpy(&args[1], bytes, length);
    const uint32_t words = 1 + (uint32_t)((length + 7) / 8);
    AsyncCompletion(action, kIOReturnSuccess, args, words);
}

void MeshCoreUSBUserClient::DeliverError(OSAction *action, IOReturn status)
{
    IOUserClientAsyncArgumentsArray args = {};
    AsyncCompletion(action, status, args, 1);
}
