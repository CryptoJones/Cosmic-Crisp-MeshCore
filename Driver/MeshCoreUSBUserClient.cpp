// MeshCoreUSBUserClient.cpp — bridges IOConnectCall* from the app to the driver.

#include <os/log.h>
#include <DriverKit/IOUserServer.h>
#include <DriverKit/IOLib.h>
#include <DriverKit/OSAction.h>
#include <DriverKit/OSData.h>
#include "MeshCoreUSBDriver.h"
#include "MeshCoreUSBUserClient.h"

// Must match `USBTransport.Selector` in the app.
enum : uint64_t {
    kSelWrite = 0,
    kSelStartRead = 1,
    kSelStopRead = 2,
};

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
    if (ivars->driver) ivars->driver->SetReadTarget(nullptr);
    return Stop(provider, SUPERDISPATCH);
}

kern_return_t MeshCoreUSBUserClient::ExternalMethod(uint64_t selector, IOUserClientMethodArguments *arguments,
                                                    const IOUserClientMethodDispatch *dispatch, OSObject *target,
                                                    void *reference)
{
    switch (selector) {
    case kSelWrite: {
        if (!arguments->structureInput) return kIOReturnBadArgument;
        return ivars->driver->WriteBytes(arguments->structureInput->getBytesNoCopy(),
                                         arguments->structureInput->getLength());
    }
    case kSelStartRead:
        if (!arguments->completion) return kIOReturnBadArgument;
        return ivars->driver->SetReadTarget(arguments->completion);
    case kSelStopRead:
        return ivars->driver->SetReadTarget(nullptr);
    default:
        return super::ExternalMethod(selector, arguments, dispatch, target, reference);
    }
}

void MeshCoreUSBUserClient::DeliverBytes(OSAction *action, const void *bytes, size_t length)
{
    // TODO: AsyncCompletion(action, kIOReturnSuccess, scalars, count) with bytes
    // staged in a shared IOMemoryDescriptor, or chunked into the 16 async scalars.
    (void)action; (void)bytes; (void)length;
}
