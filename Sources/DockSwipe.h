// Posts the private "dock swipe" gesture (three/four-finger horizontal swipe between Spaces).
// Field layout comes from Mac Mouse Fix's reverse engineering (MMF License, github.com/noah-nuebling/mac-mouse-fix).
#pragma once
#include <stdbool.h>
#include <CoreGraphics/CoreGraphics.h>

CF_IMPLICIT_BRIDGING_ENABLED
CF_ASSUME_NONNULL_BEGIN

enum { DSBegan = 1, DSChanged = 2, DSEnded = 4, DSCancelled = 8 };

// progress = cumulative offset since Began (about 1.0 = one Space). velocity only matters on Ended/Cancelled.
// Returns the CGEvent so the caller can re-post the end event; caller releases it.
CGEventRef DSCreate(int phase, double progress, double velocity) CF_RETURNS_RETAINED;
// Number of Spaces on the display containing point p (CG global coordinates).
int DSSpaceCountAt(CGPoint p);
bool DSCanPost(void);
bool DSAXTrusted(void);

CF_ASSUME_NONNULL_END
CF_IMPLICIT_BRIDGING_DISABLED
