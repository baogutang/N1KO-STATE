#include "IOHIDSensorBridge.h"
#include <dlfcn.h>
#include <dispatch/dispatch.h>

typedef CFTypeRef (*N1KO_ClientCreateFn)(CFAllocatorRef);
typedef void (*N1KO_SetMatchingFn)(CFTypeRef, CFDictionaryRef);
typedef CFArrayRef (*N1KO_CopyServicesFn)(CFTypeRef);
typedef CFTypeRef (*N1KO_CopyPropertyFn)(CFTypeRef, CFStringRef);
typedef CFTypeRef (*N1KO_CopyEventFn)(CFTypeRef, int64_t, int32_t, int64_t);
typedef double (*N1KO_GetFloatValueFn)(CFTypeRef, int32_t);

static void *n1ko_resolve(const char *symbol) {
    return dlsym(RTLD_DEFAULT, symbol);
}

CFTypeRef N1KO_IOHIDEventSystemClientCreate(CFAllocatorRef allocator) {
    static N1KO_ClientCreateFn fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (N1KO_ClientCreateFn)n1ko_resolve("IOHIDEventSystemClientCreate");
    });
    return fn ? fn(allocator) : NULL;
}

void N1KO_IOHIDEventSystemClientSetMatching(CFTypeRef client,
                                            CFDictionaryRef matching) {
    static N1KO_SetMatchingFn fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (N1KO_SetMatchingFn)n1ko_resolve("IOHIDEventSystemClientSetMatching");
    });
    if (fn) { fn(client, matching); }
}

CFArrayRef N1KO_IOHIDEventSystemClientCopyServices(CFTypeRef client) {
    static N1KO_CopyServicesFn fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (N1KO_CopyServicesFn)n1ko_resolve("IOHIDEventSystemClientCopyServices");
    });
    return fn ? fn(client) : NULL;
}

CFTypeRef N1KO_IOHIDServiceClientCopyProperty(CFTypeRef service,
                                              CFStringRef key) {
    static N1KO_CopyPropertyFn fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (N1KO_CopyPropertyFn)n1ko_resolve("IOHIDServiceClientCopyProperty");
    });
    return fn ? fn(service, key) : NULL;
}

CFTypeRef N1KO_IOHIDServiceClientCopyEvent(CFTypeRef service,
                                           int64_t type,
                                           int32_t options,
                                           int64_t timestamp) {
    static N1KO_CopyEventFn fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (N1KO_CopyEventFn)n1ko_resolve("IOHIDServiceClientCopyEvent");
    });
    return fn ? fn(service, type, options, timestamp) : NULL;
}

double N1KO_IOHIDEventGetFloatValue(CFTypeRef event, int32_t field) {
    static N1KO_GetFloatValueFn fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (N1KO_GetFloatValueFn)n1ko_resolve("IOHIDEventGetFloatValue");
    });
    return fn ? fn(event, field) : 0.0;
}
