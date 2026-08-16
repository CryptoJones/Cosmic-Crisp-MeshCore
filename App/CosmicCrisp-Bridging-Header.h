// IOKit has no Swift module map in the iOS SDK; the user-client calls the app needs
// (IOServiceOpen, IOConnectCall*Method, IONotificationPort*) are declared here.
#if !TARGET_OS_SIMULATOR && !defined(NO_USB_DRIVER)
#include <IOKit/IOKitLib.h>
#endif
#include "../Driver/MeshCoreUSBShared.h"
