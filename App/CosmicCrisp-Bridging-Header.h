// IOKit has no Swift module map in the iOS SDK; the user-client calls the app needs
// (IOServiceOpen, IOConnectCall*Method, IONotificationPort*) are declared here.
#if !TARGET_OS_SIMULATOR
#include <IOKit/IOKitLib.h>
#endif
#include "../Driver/MeshCoreUSBShared.h"
