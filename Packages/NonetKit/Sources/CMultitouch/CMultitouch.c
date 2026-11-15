#include "CMultitouch.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <os/lock.h>
#include <stdio.h>
#include <stdlib.h>

_Static_assert(sizeof(CMTTouch) == 96, "CMTTouch must match MultitouchSupport's 96-byte contact struct");

typedef void *MTDeviceRef;
typedef int (*MTContactFrameCallback)(MTDeviceRef device, CMTTouch *touches, int count, double timestamp, int frame);

static CFMutableArrayRef (*p_MTDeviceCreateList)(void);
static void (*p_MTRegisterContactFrameCallback)(MTDeviceRef, MTContactFrameCallback);
static void (*p_MTUnregisterContactFrameCallback)(MTDeviceRef, MTContactFrameCallback);
static int32_t (*p_MTDeviceStart)(MTDeviceRef, int32_t);
static int32_t (*p_MTDeviceStop)(MTDeviceRef);
static int32_t (*p_MTDeviceGetDeviceID)(MTDeviceRef, uint64_t *);
// ここから下は無くても動く
static bool (*p_MTDeviceIsBuiltIn)(MTDeviceRef);
static int32_t (*p_MTDeviceGetFamilyID)(MTDeviceRef, int32_t *);
static int32_t (*p_MTDeviceGetSensorSurfaceDimensions)(MTDeviceRef, int32_t *, int32_t *);
static CFTypeRef (*p_MTActuatorCreateFromDeviceID)(uint64_t);
static int32_t (*p_MTActuatorOpen)(CFTypeRef);
static int32_t (*p_MTActuatorClose)(CFTypeRef);
static int32_t (*p_MTActuatorActuate)(CFTypeRef, int32_t, uint32_t, float, float);

static os_unfair_lock g_load_lock = OS_UNFAIR_LOCK_INIT;
static bool g_loaded;

typedef struct {
    MTDeviceRef device;
    uint64_t deviceID;
    bool started;
} CMTRunningDevice;

// コールバックは MultitouchSupport のスレッドで呼ばれるので、動いているデバイスの表は g_lock で守る。
// コールバックは g_lock を持ったまま handler を呼ぶ。cmt_stop が g_lock を取れたら、
// それ以降 handler・context が使われることはない。
static os_unfair_lock g_lock = OS_UNFAIR_LOCK_INIT;
static CFMutableArrayRef g_list;
static CMTRunningDevice *g_running;
static int32_t g_running_count;
static CMTFrameHandler g_handler;
static void *g_context;

static CFTypeRef g_actuator;

static void write_error(char *err, int32_t errlen, const char *format, const char *detail) {
    if (err && errlen > 0) snprintf(err, (size_t)errlen, format, detail ? detail : "");
}

#define LOAD_REQUIRED(name)                                                  \
    do {                                                                     \
        p_##name = (__typeof__(p_##name))dlsym(lib, #name);                  \
        if (!p_##name) {                                                     \
            write_error(err, errlen, "symbol not found: %s", #name);         \
            return false;                                                    \
        }                                                                    \
    } while (0)

#define LOAD_OPTIONAL(name) p_##name = (__typeof__(p_##name))dlsym(lib, #name)

static bool load_locked(char *err, int32_t errlen) {
    if (g_loaded) return true;
    void *lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    if (!lib) {
        write_error(err, errlen, "dlopen failed: %s", dlerror());
        return false;
    }
    LOAD_REQUIRED(MTDeviceCreateList);
    LOAD_REQUIRED(MTRegisterContactFrameCallback);
    LOAD_REQUIRED(MTUnregisterContactFrameCallback);
    LOAD_REQUIRED(MTDeviceStart);
    LOAD_REQUIRED(MTDeviceStop);
    LOAD_REQUIRED(MTDeviceGetDeviceID);
    LOAD_OPTIONAL(MTDeviceIsBuiltIn);
    LOAD_OPTIONAL(MTDeviceGetFamilyID);
    LOAD_OPTIONAL(MTDeviceGetSensorSurfaceDimensions);
    LOAD_OPTIONAL(MTActuatorCreateFromDeviceID);
    LOAD_OPTIONAL(MTActuatorOpen);
    LOAD_OPTIONAL(MTActuatorClose);
    LOAD_OPTIONAL(MTActuatorActuate);
    g_loaded = true;
    return true;
}

bool cmt_load(char *err, int32_t errlen) {
    os_unfair_lock_lock(&g_load_lock);
    bool loaded = load_locked(err, errlen);
    os_unfair_lock_unlock(&g_load_lock);
    return loaded;
}

static bool is_loaded(void) {
    os_unfair_lock_lock(&g_load_lock);
    bool loaded = g_loaded;
    os_unfair_lock_unlock(&g_load_lock);
    return loaded;
}

static uint64_t device_id(MTDeviceRef device) {
    uint64_t value = 0;
    p_MTDeviceGetDeviceID(device, &value);
    return value;
}

static void fill_info(MTDeviceRef device, CMTDeviceInfo *info) {
    info->deviceID = device_id(device);
    info->builtIn = p_MTDeviceIsBuiltIn ? p_MTDeviceIsBuiltIn(device) : false;
    info->familyID = 0;
    if (p_MTDeviceGetFamilyID) p_MTDeviceGetFamilyID(device, &info->familyID);
    info->surfaceWidth = 0;
    info->surfaceHeight = 0;
    if (p_MTDeviceGetSensorSurfaceDimensions &&
        p_MTDeviceGetSensorSurfaceDimensions(device, &info->surfaceWidth, &info->surfaceHeight) != 0) {
        info->surfaceWidth = 0;
        info->surfaceHeight = 0;
    }
}

int32_t cmt_list_devices(CMTDeviceInfo *out, int32_t capacity) {
    if (!is_loaded()) return -1;
    // MTDeviceCreateList は呼ぶたびに新しい配列（+1）と新しいデバイスを返す（確認済み）
    CFMutableArrayRef list = p_MTDeviceCreateList();
    if (!list) return 0;
    CFIndex count = CFArrayGetCount(list);
    for (CFIndex i = 0; i < count && i < capacity; i++) {
        if (out) fill_info((MTDeviceRef)CFArrayGetValueAtIndex(list, i), &out[i]);
    }
    CFRelease(list);
    return (int32_t)count;
}

static int frame_callback(MTDeviceRef device, CMTTouch *touches, int count, double timestamp, int frame) {
    (void)frame;
    os_unfair_lock_lock(&g_lock);
    if (g_handler) {
        for (int32_t i = 0; i < g_running_count; i++) {
            if (g_running[i].device == device) {
                g_handler(g_context, g_running[i].deviceID, touches, count, timestamp);
                break;
            }
        }
    }
    os_unfair_lock_unlock(&g_lock);
    return 0;
}

static bool contains(const uint64_t *ids, int32_t count, uint64_t value) {
    for (int32_t i = 0; i < count; i++) {
        if (ids[i] == value) return true;
    }
    return false;
}

int32_t cmt_start(const uint64_t *deviceIDs, int32_t idCount, CMTFrameHandler handler, void *context, uint64_t *startedIDs) {
    cmt_stop();
    if (!is_loaded() || !handler || !deviceIDs || idCount <= 0) return 0;
    CFMutableArrayRef list = p_MTDeviceCreateList();
    if (!list) return 0;
    CFIndex count = CFArrayGetCount(list);
    CMTRunningDevice *running = count > 0 ? calloc((size_t)count, sizeof(CMTRunningDevice)) : NULL;
    if (!running) {
        CFRelease(list);
        return 0;
    }
    int32_t runningCount = 0;
    for (CFIndex i = 0; i < count; i++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(list, i);
        uint64_t identifier = device_id(device);
        if (!contains(deviceIDs, idCount, identifier)) continue;
        running[runningCount].device = device;
        running[runningCount].deviceID = identifier;
        runningCount++;
    }

    // 表を公開してから登録する（先に登録すると、最初のフレームが表に無くて捨てられる）
    os_unfair_lock_lock(&g_lock);
    g_list = list;
    g_running = running;
    g_running_count = runningCount;
    g_handler = handler;
    g_context = context;
    os_unfair_lock_unlock(&g_lock);

    int32_t started = 0;
    for (int32_t i = 0; i < runningCount; i++) {
        MTDeviceRef device = running[i].device;
        p_MTRegisterContactFrameCallback(device, frame_callback);
        if (p_MTDeviceStart(device, 0) == 0) {
            running[i].started = true;
            if (startedIDs && started < idCount) startedIDs[started] = running[i].deviceID;
            started++;
        } else {
            p_MTUnregisterContactFrameCallback(device, frame_callback);
        }
    }
    return started;
}

void cmt_stop(void) {
    os_unfair_lock_lock(&g_lock);
    CFMutableArrayRef list = g_list;
    CMTRunningDevice *running = g_running;
    int32_t count = g_running_count;
    g_list = NULL;
    g_running = NULL;
    g_running_count = 0;
    g_handler = NULL;
    g_context = NULL;
    os_unfair_lock_unlock(&g_lock);

    // 登録の解除は g_lock の外で行う（解除がコールバックの終わりを待つ場合に詰まらないように）
    for (int32_t i = 0; i < count; i++) {
        if (!running[i].started) continue;
        p_MTUnregisterContactFrameCallback(running[i].device, frame_callback);
        p_MTDeviceStop(running[i].device);
    }
    free(running);
    if (list) CFRelease(list);
}

int32_t cmt_actuator_open(uint64_t deviceID) {
    cmt_actuator_close();
    if (!is_loaded() || !p_MTActuatorCreateFromDeviceID || !p_MTActuatorOpen || !p_MTActuatorActuate) return -1;
    CFTypeRef actuator = p_MTActuatorCreateFromDeviceID(deviceID);
    if (!actuator) return -1;
    int32_t result = p_MTActuatorOpen(actuator);
    if (result != 0) {
        CFRelease(actuator);
        return result;
    }
    g_actuator = actuator;
    return 0;
}

int32_t cmt_actuator_actuate(int32_t actuationID, uint32_t unknown1, float unknown2, float unknown3) {
    if (!g_actuator) return -1;
    return p_MTActuatorActuate(g_actuator, actuationID, unknown1, unknown2, unknown3);
}

void cmt_actuator_close(void) {
    if (!g_actuator) return;
    if (p_MTActuatorClose) p_MTActuatorClose(g_actuator);
    CFRelease(g_actuator);
    g_actuator = NULL;
}
