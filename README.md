# SpaceSwipe

A small macOS menu bar app that makes the **Logitech MX Master thumb wheel** (or any horizontal scroll) act like a **trackpad swipe between Spaces, but only while Mission Control is open**.

Outside Mission Control, horizontal scrolling passes through untouched, with one opt-in exception: **hold the middle button (wheel click) and turn the thumb wheel to switch Spaces anywhere** (see [Middle button](#middle-button)).

- The Space follows the wheel 1:1, the way it follows your fingers on a trackpad.
- Turn back while the wheel is still moving and the Space comes back with it.
- When the wheel stops, a swipe past 60% of a Space finishes with macOS's own animation. Anything shorter snaps back.
- No Dock icon. A menu bar toggle turns it on and off.

Built and tested on macOS 27.2 (Apple Silicon) with an MX Master 3S, Logi Options+ and Mac Mouse Fix running.

## Install

Requires Xcode (or its command line tools) and macOS 27.

```sh
git clone https://github.com/anishmanchanda/SpaceSwipe.git
cd SpaceSwipe
./build.sh                       # builds, signs, self-tests, installs to /Applications
open /Applications/SpaceSwipe.app
```

`build.sh` signs with your first code-signing identity (an Apple Development certificate works). Keeping the same identity keeps the Accessibility permission valid across rebuilds. Without one, it falls back to ad-hoc signing, and you'll need to re-grant the permission after every build.

### Permission

Only **Accessibility** is needed: System Settings → Privacy & Security → Accessibility → enable **SpaceSwipe**.
The app asks on first launch. The menu shows "Waiting for Accessibility permission…" until it's granted, and starts by itself once it is.

## Settings

Menu bar icon → **Edit Settings…** opens
`~/Library/Application Support/SpaceSwipe/settings.json`. After saving, choose **Reload Settings** (no relaunch needed).

```json
{
  "pointsPerSpace": 500,
  "commitAt": 0.6,
  "idleEnd": 0.15,
  "reverse": false,
  "middleButtonSwipe": true,
  "swipeButton": 2
}
```

| Key | What it does | Default | Try |
|---|---|---|---|
| `pointsPerSpace` | How much wheel travel (scroll points) moves one full Space. Lower = the Space follows the wheel faster. | `500` | `350` snappy · `500` balanced · `700` precise |
| `commitAt` | How far (fraction of a Space) you must swipe for a stop to switch. Below it, snaps back. | `0.6` | `0.5` trackpad-like · `0.6` deliberate · `0.4` eager |
| `idleEnd` | Seconds without wheel input that count as "stopped", if the mouse driver doesn't report the end of the motion itself. | `0.15` | `0.1` quicker · `0.25` if it decides while you're still turning slowly |
| `reverse` | Flip the direction. | `false` | `true` if it feels backwards |
| `middleButtonSwipe` | Hold a mouse button and turn the thumb wheel to switch Spaces anywhere. | `true` | `false` if you rely on instant middle clicks or middle-drag |
| `swipeButton` | Which button: `2` middle (wheel click), `3` back, `4` forward. | `2` | `3` for the thumb button, if something else already uses the middle button |

**Suggested starting points**

- *Feels like a trackpad:* `pointsPerSpace 400`, `commitAt 0.5`
- *Hard to switch by accident:* `pointsPerSpace 600`, `commitAt 0.65`
- *One small flick per Space:* `pointsPerSpace 300`, `commitAt 0.45`

## Middle button

With `middleButtonSwipe` on, holding the middle button while turning the thumb wheel does the same swipe as in Mission Control, in any app. Letting go of the button counts as lifting your fingers.

To tell a click from the start of a swipe, SpaceSwipe holds the press back until something happens:

- **Release with no scrolling:** the click is replayed, so a middle click registers when you let go instead of when you press.
- **Cursor moves more than 8 points while held:** treated as a middle-drag. The press is replayed and the wheel no longer swipes until you release.
- **Wheel turned while held:** the press is swallowed, so no stray click lands when you let go.

**Mac Mouse Fix conflict:** Mac Mouse Fix swallows any button that has actions assigned to it, and only replays a click on release. SpaceSwipe never sees that button held (neither the event tap, the system's button state, nor GameController does), so the swipe can't start. Quit Mac Mouse Fix, or remove its actions for that button, or point `swipeButton` at a button it doesn't use.

## Debugging

Menu → **Debug logging** writes to `~/Library/Logs/SpaceSwipe.log`. It logs raw scroll fields, Mission Control detection and each release decision:

```sh
grep release ~/Library/Logs/SpaceSwipe.log | tail
```

## How it works

1. **Event tap:** a `CGEventTap` sees scroll events and middle-button events. Vertical or non-horizontal scroll returns immediately and untouched.
2. **Mission Control detection:** on macOS 27, Mission Control belongs to `com.apple.WindowManager`, not the Dock. The accessibility element under the cursor (or one of its parents) has an `AXIdentifier` of `mc.*` or `*.space.N`. That check runs on a background queue and is cached, so the tap never waits on it. While a swipe is running, the check is paused, because Mission Control shows the next Space's real windows mid-swipe and would otherwise look closed.
3. **Swipe:** horizontal wheel input becomes the private *dock swipe* gesture (began → changed → ended/cancelled), posted outside the tap callback. On macOS 27 this is an `IOHIDEvent` (type `DockSwipe`, horizontal motion, progress = cumulative offset) attached to a CGEvent with SkyLight's `SLEventSetIOHIDEvent`. The end event is re-sent at 0.2 s and 0.5 s so the transition can't get stuck.
4. **Decision:** when the wheel stops (the driver's scroll-ended phase, or `idleEnd`), progress ≥ `commitAt` sends *ended* and macOS animates the rest of the way. Otherwise it sends *cancelled* and the Space snaps back.

`proto/proto.c` is the small prototype used to check that the private events still work on macOS 27. It posts one swipe (`proto left|right [delay]`) and reports whether the active Space changed.

## Notes

- Uses private macOS APIs (SkyLight, IOHIDEvent). A future macOS update may break it.
- If you also have the Hammerspoon Ctrl+Arrow version running, stop it (`spaceScroll:stop()` in the Hammerspoon console). Otherwise both react to the wheel.

## Credits

The dock-swipe event layout and the one-Space offset formula come from the reverse engineering in
[Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix) by Noah Nuebling (MMF License).
No Mac Mouse Fix source code is copied. This project is derived from that research.
