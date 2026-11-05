#include "DockSwipe.h"
#include <ApplicationServices/ApplicationServices.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
extern IOHIDEventRef IOHIDEventCreate(CFAllocatorRef, uint32_t type, uint64_t timestamp, uint32_t options);
extern void IOHIDEventSetIntegerValue(IOHIDEventRef, uint32_t field, CFIndex value);
extern void IOHIDEventSetDoubleValue(IOHIDEventRef, uint32_t field, double value);
extern void IOHIDEventAppendEvent(IOHIDEventRef parent, IOHIDEventRef child, uint32_t options);
extern void SLEventSetIOHIDEvent(CGEventRef, IOHIDEventRef); // SkyLight

enum { kTypeVelocity = 9, kTypeDockSwipe = 23, kFlavorDockPrimary = 3, kMotionHorizontal = 1, kPhaseShift = 24 };
#define FIELD(type, i) (((uint32_t)(type) << 16) | (i))

CGEventRef DSCreate(int phase, double progress, double velocity) {
    IOHIDEventRef hid = IOHIDEventCreate(kCFAllocatorDefault, kTypeDockSwipe, 0, (uint32_t)phase << kPhaseShift);
    IOHIDEventSetIntegerValue(hid, FIELD(kTypeDockSwipe, 1), kMotionHorizontal);
    IOHIDEventSetIntegerValue(hid, FIELD(kTypeDockSwipe, 5), kFlavorDockPrimary);
    IOHIDEventSetDoubleValue(hid, FIELD(kTypeDockSwipe, 2), progress);
    if (phase == DSEnded || phase == DSCancelled) {
        IOHIDEventRef v = IOHIDEventCreate(kCFAllocatorDefault, kTypeVelocity, 0, 0);
        IOHIDEventSetDoubleValue(v, FIELD(kTypeVelocity, 0), velocity);
        IOHIDEventSetDoubleValue(v, FIELD(kTypeVelocity, 1), velocity);
        IOHIDEventAppendEvent(hid, v, 0);
        CFRelease(v);
    }
    CGEventRef e = CGEventCreate(NULL);
    CGEventSetType(e, (CGEventType)30);
    SLEventSetIOHIDEvent(e, hid); // SkyLight copies the HID event (verified), so we release ours
    CFRelease(hid);
    return e;
}

extern int SLSMainConnectionID(void);
extern CFArrayRef SLSCopyManagedDisplaySpaces(int);

int DSSpaceCountAt(CGPoint p) {
    CGDirectDisplayID d = CGMainDisplayID(); uint32_t n = 0;
    CGGetDisplaysWithPoint(p, 1, &d, &n);
    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(d);
    CFStringRef want = uuid ? CFUUIDCreateString(NULL, uuid) : NULL;
    CFArrayRef displays = SLSCopyManagedDisplaySpaces(SLSMainConnectionID());
    int match = 0, most = 0;
    for (CFIndex i = 0; displays && i < CFArrayGetCount(displays); i++) {
        CFDictionaryRef dict = CFArrayGetValueAtIndex(displays, i);
        CFArrayRef spaces = CFDictionaryGetValue(dict, CFSTR("Spaces"));
        int count = spaces ? (int)CFArrayGetCount(spaces) : 0;
        if (count > most) most = count;
        CFStringRef id = CFDictionaryGetValue(dict, CFSTR("Display Identifier"));
        if (want && id && CFStringCompare(id, want, kCFCompareCaseInsensitive) == kCFCompareEqualTo) match = count;
    }
    if (displays) CFRelease(displays);
    if (want) CFRelease(want);
    if (uuid) CFRelease(uuid);
    return match ? match : most; // "Displays have separate Spaces" off: one entry named "Main"
}

bool DSCanPost(void) { return CGPreflightPostEventAccess(); }
bool DSAXTrusted(void) { return AXIsProcessTrusted(); }
