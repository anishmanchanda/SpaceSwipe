// Prototype: posts one horizontal dock swipe. Usage: proto left|right [delaySeconds]
#include "../Sources/DockSwipe.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

extern int SLSMainConnectionID(void);
extern uint64_t SLSGetActiveSpace(int);
static uint64_t space(void) { return SLSGetActiveSpace(SLSMainConnectionID()); }

static void post(CGEventRef e) { CGEventPost(kCGSessionEventTap, e); }

int main(int argc, char **argv) {
    double dir = (argc > 1 && strcmp(argv[1], "left") == 0) ? -1 : 1;
    int delay = argc > 2 ? atoi(argv[2]) : 0;
    printf("PostEvent access: %d, Accessibility: %d\n", DSCanPost(), DSAXTrusted());
    if (!DSCanPost()) { CGRequestPostEventAccess(); printf("No permission to post events. Grant it, then rerun.\n"); return 1; }
    if (delay) { printf("Swiping in %d s...\n", delay); sleep(delay); }

    uint64_t before = space();
    double step = dir * 0.035, offset = step;
    CGEventRef e = DSCreate(DSBegan, offset, 0); post(e); CFRelease(e);
    for (int i = 0; i < 20; i++) { usleep(16000); offset += step; e = DSCreate(DSChanged, offset, 0); post(e); CFRelease(e); }
    usleep(16000);
    e = DSCreate(DSEnded, offset, step * 100);
    post(e); usleep(200000); post(e); usleep(300000); post(e); // MMF re-sends end to avoid stuck transitions
    CFRelease(e);
    usleep(500000);
    uint64_t after = space();
    printf("Posted %s swipe, final offset %.2f. Active Space %llu -> %llu: %s\n", dir < 0 ? "left" : "right", offset, before, after, before != after ? "SPACE CHANGED" : "no change");
    return 0;
}
