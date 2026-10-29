#include "CMultitouch.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdio.h>

_Static_assert(sizeof(CMTTouch) == 96, "CMTTouch must match MultitouchSupport's 96-byte contact struct");

typedef void *MTDeviceRef;
typedef int (*MTContactFrameCallback)(MTDeviceRef device, CMTTouch *touches, int count, double timestamp, int frame);

static CFMutableArrayRef (*p_MTDeviceCreateList)(void);
static void (*p_MTRegisterContactFrameCallback)(MTDeviceRef, MTContactFrameCallback);
static void (*p_MTUnregisterContactFrameCallback)(MTDeviceRef, MTContactFrameCallback);
static int32_t (*p_MTDeviceStart)(MTDeviceRef, int32_t);
static int32_t (*p_MTDeviceStop)(MTDeviceRef);
static bool (*p_MTDeviceIsBuiltIn)(MTDeviceRef);
static int32_t (*p_MTDeviceGetFamilyID)(MTDeviceRef, int32_t *);
static int32_t (*p_MTDeviceGetDeviceID)(MTDeviceRef, uint64_t *);
static int32_t (*p_MTDeviceGetSensorSurfaceDimensions)(MTDeviceRef, int32_t *, int32_t *);
static CFTypeRef (*p_MTActuatorCreateFromDeviceID)(uint64_t);
static int32_t (*p_MTActuatorOpen)(CFTypeRef);
static int32_t (*p_MTActuatorClose)(CFTypeRef);
static int32_t (*p_MTActuatorActuate)(CFTypeRef, int32_t, uint32_t, float, float);

static CFMutableArrayRef g_devices;
static CMTFrameHandler g_handler;
static CFTypeRef g_actuator;

#define LOAD(name)                                                       \
    do {                                                                 \
        p_##name = (__typeof__(p_##name))dlsym(lib, #name);              \
        if (!p_##name) {                                                 \
            snprintf(err, (size_t)errlen, "symbol not found: %s", #name); \
            return false;                                                \
        }                                                                \
    } while (0)

bool cmt_load(char *err, int32_t errlen) {
    if (g_devices) return true;
    void *lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (!lib) {
        snprintf(err, (size_t)errlen, "dlopen failed: %s", dlerror());
        return false;
    }
    LOAD(MTDeviceCreateList);
    LOAD(MTRegisterContactFrameCallback);
    LOAD(MTUnregisterContactFrameCallback);
    LOAD(MTDeviceStart);
    LOAD(MTDeviceStop);
    LOAD(MTDeviceIsBuiltIn);
    LOAD(MTDeviceGetFamilyID);
    LOAD(MTDeviceGetDeviceID);
    LOAD(MTDeviceGetSensorSurfaceDimensions);
    LOAD(MTActuatorCreateFromDeviceID);
    LOAD(MTActuatorOpen);
    LOAD(MTActuatorClose);
    LOAD(MTActuatorActuate);

    g_devices = p_MTDeviceCreateList();
    if (!g_devices) {
        snprintf(err, (size_t)errlen, "MTDeviceCreateList returned NULL");
        return false;
    }
    return true;
}

static MTDeviceRef device_at(int32_t index) {
    if (!g_devices || index < 0 || index >= CFArrayGetCount(g_devices)) return NULL;
    return (MTDeviceRef)CFArrayGetValueAtIndex(g_devices, index);
}

static int32_t index_of(MTDeviceRef device) {
    if (!g_devices) return -1;
    CFIndex count = CFArrayGetCount(g_devices);
    for (CFIndex i = 0; i < count; i++) {
        if (CFArrayGetValueAtIndex(g_devices, i) == device) return (int32_t)i;
    }
    return -1;
}

int32_t cmt_device_count(void) {
    return g_devices ? (int32_t)CFArrayGetCount(g_devices) : 0;
}

bool cmt_device_is_builtin(int32_t index) {
    MTDeviceRef device = device_at(index);
    return device && p_MTDeviceIsBuiltIn(device);
}

int32_t cmt_device_family_id(int32_t index) {
    int32_t value = 0;
    MTDeviceRef device = device_at(index);
    if (device) p_MTDeviceGetFamilyID(device, &value);
    return value;
}

uint64_t cmt_device_id(int32_t index) {
    uint64_t value = 0;
    MTDeviceRef device = device_at(index);
    if (device) p_MTDeviceGetDeviceID(device, &value);
    return value;
}

bool cmt_device_surface_size(int32_t index, int32_t *width, int32_t *height) {
    MTDeviceRef device = device_at(index);
    return device && p_MTDeviceGetSensorSurfaceDimensions(device, width, height) == 0;
}

static int frame_callback(MTDeviceRef device, CMTTouch *touches, int count, double timestamp, int frame) {
    (void)frame;
    CMTFrameHandler handler = g_handler;
    if (handler) handler(index_of(device), touches, count, timestamp);
    return 0;
}

void cmt_start(CMTFrameHandler handler) {
    g_handler = handler;
    for (int32_t i = 0; i < cmt_device_count(); i++) {
        MTDeviceRef device = device_at(i);
        p_MTRegisterContactFrameCallback(device, frame_callback);
        p_MTDeviceStart(device, 0);
    }
}

void cmt_stop(void) {
    for (int32_t i = 0; i < cmt_device_count(); i++) {
        MTDeviceRef device = device_at(i);
        p_MTUnregisterContactFrameCallback(device, frame_callback);
        p_MTDeviceStop(device);
    }
    g_handler = NULL;
}

int32_t cmt_actuator_open(int32_t deviceIndex) {
    cmt_actuator_close();
    if (!p_MTActuatorCreateFromDeviceID) return -1;
    g_actuator = p_MTActuatorCreateFromDeviceID(cmt_device_id(deviceIndex));
    if (!g_actuator) return -1;
    int32_t result = p_MTActuatorOpen(g_actuator);
    if (result != 0) {
        CFRelease(g_actuator);
        g_actuator = NULL;
    }
    return result;
}

int32_t cmt_actuator_actuate(int32_t actuationID, uint32_t unknown1, float unknown2, float unknown3) {
    if (!g_actuator) return -1;
    return p_MTActuatorActuate(g_actuator, actuationID, unknown1, unknown2, unknown3);
}

void cmt_actuator_close(void) {
    if (!g_actuator) return;
    p_MTActuatorClose(g_actuator);
    CFRelease(g_actuator);
    g_actuator = NULL;
}
