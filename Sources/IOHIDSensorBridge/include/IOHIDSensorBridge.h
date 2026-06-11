#ifndef IOHID_SENSOR_BRIDGE_H
#define IOHID_SENSOR_BRIDGE_H

#include <CoreFoundation/CoreFoundation.h>

// ----------------------------------------------------------------------------
// Private IOKit / IOHIDFamily symbols for reading Apple Silicon sensors.
//
// Resolved at runtime via dlsym so missing symbols on some macOS versions do
// not cause dyld "Symbol not found" crashes at launch.
// ----------------------------------------------------------------------------

CF_ASSUME_NONNULL_BEGIN

CFTypeRef _Nullable N1KO_IOHIDEventSystemClientCreate(CFAllocatorRef _Nullable allocator)
    CF_RETURNS_RETAINED;

void N1KO_IOHIDEventSystemClientSetMatching(CFTypeRef client,
                                            CFDictionaryRef _Nullable matching);

CFArrayRef _Nullable N1KO_IOHIDEventSystemClientCopyServices(CFTypeRef client)
    CF_RETURNS_RETAINED;

CFTypeRef _Nullable N1KO_IOHIDServiceClientCopyProperty(CFTypeRef service,
                                                        CFStringRef key)
    CF_RETURNS_RETAINED;

CFTypeRef _Nullable N1KO_IOHIDServiceClientCopyEvent(CFTypeRef service,
                                                     int64_t type,
                                                     int32_t options,
                                                     int64_t timestamp)
    CF_RETURNS_RETAINED;

double N1KO_IOHIDEventGetFloatValue(CFTypeRef event, int32_t field);

CF_ASSUME_NONNULL_END

#endif /* IOHID_SENSOR_BRIDGE_H */
