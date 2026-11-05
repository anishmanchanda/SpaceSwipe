// SpaceSwipe: while Mission Control is open, turns horizontal scroll (MX Master thumb wheel)
// into a real trackpad-style Space swipe. Everywhere else, scroll events pass through untouched.
import Cocoa
import ApplicationServices
import QuartzCore

// MARK: Settings — edit from the menu bar (Edit Settings…), then Reload Settings. See README for suggested values.

let defaults = UserDefaults.standard
let settingsURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/SpaceSwipe/settings.json")
let defaultSettings: [String: Any] = [
    "pointsPerSpace": 500.0, // wheel travel (scroll points) for one full Space; lower = more sensitive
    "commitAt": 0.6,         // fraction of a Space past which a stop switches; below it snaps back
    "idleEnd": 0.15,         // seconds without wheel input that count as "stopped" (fallback)
    "reverse": false,        // flip the swipe direction
]
var pointsPerSpace = 500.0, commitAt = 0.6, idleEnd = 0.15, reverse = false

func loadSettings() {
    let fm = FileManager.default
    if !fm.fileExists(atPath: settingsURL.path) {
        try? fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = "{\n  \"pointsPerSpace\": 500,\n  \"commitAt\": 0.6,\n  \"idleEnd\": 0.15,\n  \"reverse\": false\n}\n"
        fm.createFile(atPath: settingsURL.path, contents: text.data(using: .utf8))
    }
    var s = defaultSettings
    if let data = try? Data(contentsOf: settingsURL),
       let file = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { s.merge(file) { _, new in new } }
    else { NSLog("SpaceSwipe: settings.json is not valid JSON, using defaults") }
    pointsPerSpace = max((s["pointsPerSpace"] as? NSNumber)?.doubleValue ?? 500, 1)
    commitAt = (s["commitAt"] as? NSNumber)?.doubleValue ?? 0.6
    idleEnd = max((s["idleEnd"] as? NSNumber)?.doubleValue ?? 0.15, 0.02)
    reverse = (s["reverse"] as? Bool) ?? false
}
var enabled = defaults.object(forKey: "enabled") as? Bool ?? true
var debug = defaults.bool(forKey: "debug")

// MARK: Logging (only when "Debug logging" is on)

let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SpaceSwipe.log")
let logQueue = DispatchQueue(label: "log")
func log(_ s: @autoclosure () -> String) {
    guard debug else { return }
    let line = "\(Date().formatted(.iso8601.time(includingFractionalSeconds: true))) \(s())\n"
    logQueue.async {
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
        else { try? line.write(to: logURL, atomically: false, encoding: .utf8) }
    }
}

// MARK: Mission Control detection (macOS 27: owned by WindowManager, AX identifiers mc.* / *.space.N)

func isMCIdentifier(_ id: String) -> Bool {
    id.hasPrefix("mc.") || id.range(of: #"\.space\.\d+$"#, options: .regularExpression) != nil
}

let systemWide: AXUIElement = {
    let e = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(e, 0.1)
    return e
}()

enum MCCheck { case open, closed(String), unsure(String) }

// "closed" only when another app is clearly under the cursor. While Mission Control animates
// between Spaces the element under the cursor briefly stops looking like MC; that's "unsure".
func checkMC() -> MCCheck {
    guard let loc = CGEvent(source: nil)?.location else { return .unsure("no cursor location") }
    var hit: AXUIElement?
    let err = AXUIElementCopyElementAtPosition(systemWide, Float(loc.x), Float(loc.y), &hit)
    guard err == .success, var el = hit else { return .unsure("AX error \(err.rawValue)") }
    var pid: pid_t = 0
    AXUIElementGetPid(el, &pid)
    let owner = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid \(pid)"
    guard owner == "com.apple.WindowManager" else { return .closed(owner) }
    var ids: [String] = []
    for _ in 0..<8 {
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, "AXIdentifier" as CFString, &v) == .success, let id = v as? String {
            if isMCIdentifier(id) { return .open }
            ids.append(id)
        }
        var p: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &p) == .success, let parent = p else { break }
        el = parent as! AXUIElement
    }
    return .unsure("WindowManager, ids \(ids)")
}

// The AX query runs off the main thread so the event tap never waits on it.
// The tap decides from the cached value; a poll keeps it fresh around Mission Control use.
let axQueue = DispatchQueue(label: "ax", qos: .userInteractive)
let mcLock = NSLock()
var mcOpen = false, mcCheckedAt = 0.0, mcChecking = false, mcUnsureSince: Double?, mcClosedAt = 0.0
// During a swipe MC shows the next Space's real windows, so AX reports e.g. Terminal under the cursor.
// Until this time, a swipe is running (or animating) and "closed" results are ignored.
var mcHoldUntil = 0.0
func holdMC(_ seconds: Double) { mcLock.lock(); mcHoldUntil = max(mcHoldUntil, CACurrentMediaTime() + seconds); mcLock.unlock() }
let unsureGrace = 0.5 // seconds of "unsure" before we believe MC is closed
var mcPoll: Timer?

func refreshMC(maxAge: Double = 0.1) {
    mcLock.lock(); defer { mcLock.unlock() }
    guard !mcChecking, CACurrentMediaTime() - mcCheckedAt > maxAge else { return }
    mcChecking = true
    axQueue.async {
        let result = checkMC()
        let now = CACurrentMediaTime()
        mcLock.lock()
        let was = mcOpen
        var reason = ""
        switch now < mcHoldUntil && mcOpen ? .open : result {
        case .open: mcOpen = true; mcUnsureSince = nil
        case .closed(let r): mcOpen = false; mcUnsureSince = nil; reason = "closed: \(r)"
        case .unsure(let r):
            reason = "unsure: \(r)"
            if mcOpen {
                if mcUnsureSince == nil { mcUnsureSince = now }
                if now - mcUnsureSince! > unsureGrace { mcOpen = false; reason += " (for \(unsureGrace)s)" }
            }
        }
        let open = mcOpen
        if was && !open { mcClosedAt = now }
        mcCheckedAt = now; mcChecking = false
        mcLock.unlock()
        DispatchQueue.main.async {
            if open != was { log("Mission Control \(open ? "OPEN" : "closed") \(reason)") }
            else if open && !reason.isEmpty { log("MC check \(reason) (keeping open)") }
            if open || gesture.active || now - mcClosedAt < 2 {
                if mcPoll == nil { mcPoll = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in refreshMC() } }
            } else { mcPoll?.invalidate(); mcPoll = nil }
        }
    }
}
var mcIsOpen: Bool { mcLock.lock(); defer { mcLock.unlock() }; return mcOpen }

// MARK: Swipe gesture (main thread only; events are posted outside the tap callback)

// When the wheel stops (= fingers lifted): past `commitAt` of a Space switches, otherwise snap back.
func shouldCommit(progress: Double, commitAt: Double = commitAt) -> Bool { abs(progress) >= commitAt }

// Swipe progress for one full Space, measured by Mac Mouse Fix (depends on the number of Spaces).
func oneSpaceOffset(spaces n: Int) -> Double { n <= 1 ? 2.0 : 1.0 + 1.0 / Double(n - 1) }

final class Gesture {
    var active = false, offset = 0.0, lastStep = 0.0, oneSpace = 2.0
    var idleTimer: Timer?, resend: [Timer] = []
    var progress: Double { offset / oneSpace }

    func feed(_ delta: Double, wheelStopped: Bool) {
        let began = !active
        if began {
            resend.forEach { $0.invalidate() }; resend = []
            oneSpace = oneSpaceOffset(spaces: Int(DSSpaceCountAt(CGEvent(source: nil)?.location ?? .zero)))
            active = true; offset = 0
        }
        let step = delta / pointsPerSpace * oneSpace * (reverse ? -1 : 1)
        offset += step
        lastStep = step
        send(began ? Int32(DSBegan) : Int32(DSChanged))
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleEnd, repeats: false) { [weak self] _ in self?.finish() }
        holdMC(idleEnd + 0.8)
        refreshMC() // keep the MC poll running while a swipe is active
        if wheelStopped { finish() }
    }

    func cancel() { finish(forceCancel: true) }

    func finish(forceCancel: Bool = false) {
        guard active else { return }
        idleTimer?.invalidate(); idleTimer = nil
        holdMC(0.8) // let the finish/snap-back animation play
        let commit = !forceCancel && shouldCommit(progress: progress)
        log("release progress=\(progress) -> \(commit ? "commit" : "cancel")")
        guard commit else { active = false; postEnd(Int32(DSCancelled), velocity: 0); return }

        // Already past halfway, so macOS plays its own trackpad completion animation from here.
        active = false
        postEnd(Int32(DSEnded), velocity: lastStep * 100)
    }

    private func postEnd(_ phase: Int32, velocity: Double) {
        let e = DSCreate(phase, offset, velocity)
        e.post(tap: .cgSessionEventTap)
        // macOS sometimes drops the end event and leaves the transition stuck; re-send it like MMF does.
        resend = [0.2, 0.5].map { t in Timer.scheduledTimer(withTimeInterval: t, repeats: false) { _ in e.post(tap: .cgSessionEventTap) } }
        log("swipe \(phase == DSEnded ? "ENDED" : "CANCELLED") offset=\(offset) oneSpace=\(oneSpace)")
    }

    private func send(_ phase: Int32) {
        DSCreate(phase, offset, 0).post(tap: .cgSessionEventTap)
        log("swipe phase=\(phase) offset=\(offset)")
    }
}
let gesture = Gesture()

// MARK: Event tap

var tap: CFMachPort?

let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    let pass = Unmanaged.passUnretained(event)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        log("tap disabled (\(type.rawValue)), re-enabling")
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return pass
    }
    guard enabled, type == .scrollWheel else { return pass }
    let line = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
    let point = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
    guard line != 0 || point != 0 else { return pass }                              // not horizontal: untouched
    guard abs(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)) <= abs(point) else { return pass }

    refreshMC()                                                                      // async, never blocks
    let open = mcIsOpen
    log("h-scroll line=\(line) point=\(point) cont=\(event.getIntegerValueField(.scrollWheelEventIsContinuous)) phase=\(event.getIntegerValueField(.scrollWheelEventScrollPhase)) momentum=\(event.getIntegerValueField(.scrollWheelEventMomentumPhase)) mc=\(open)")
    guard open else { return pass }
    let delta = point != 0 ? point : Double(line) * 10
    let stopped = [4, 8].contains(event.getIntegerValueField(.scrollWheelEventScrollPhase)) // wheel driver says motion ended
    DispatchQueue.main.async { gesture.feed(delta, wheelStopped: stopped) }
    return nil                                                                       // swallow: MC gets the swipe instead
}

func startTap() -> Bool {
    let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
    guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                    eventsOfInterest: mask, callback: tapCallback, userInfo: nil) else { return false }
    tap = t
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
    CGEvent.tapEnable(tap: t, enable: true)
    log("event tap started")
    return true
}

// MARK: Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    let debugItem = NSMenuItem(title: "Debug logging", action: #selector(toggleDebug), keyEquivalent: "")
    let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ n: Notification) {
        let menu = NSMenu()
        for i in [statusLine, .separator(), enabledItem, debugItem] { menu.addItem(i) }
        menu.addItem(NSMenuItem(title: "Edit Settings…", action: #selector(editSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Reload Settings", action: #selector(reloadSettings), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Open Log", action: #selector(openLog), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SpaceSwipe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        item.menu = menu
        update()

        // Asks once for Accessibility; the tap can't be created until it's granted, so retry.
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        if !startTap() {
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                if startTap() { t.invalidate(); self?.update() }
            }
        }
    }

    func update() {
        enabledItem.state = enabled ? .on : .off
        debugItem.state = debug ? .on : .off
        statusLine.title = tap == nil ? "Waiting for Accessibility permission…" : (enabled ? "Active in Mission Control" : "Off")
        item.button?.image = NSImage(systemSymbolName: enabled ? "rectangle.split.3x1.fill" : "rectangle.split.3x1",
                                     accessibilityDescription: "SpaceSwipe")
    }

    @objc func toggleEnabled() {
        enabled.toggle(); defaults.set(enabled, forKey: "enabled")
        if !enabled { gesture.cancel() }
        update()
    }
    @objc func toggleDebug() { debug.toggle(); defaults.set(debug, forKey: "debug"); update(); log("debug logging on") }
    @objc func editSettings() { loadSettings(); NSWorkspace.shared.open(settingsURL) }
    @objc func reloadSettings() { loadSettings(); log("settings: pointsPerSpace=\(pointsPerSpace) commitAt=\(commitAt) idleEnd=\(idleEnd) reverse=\(reverse)") }
    @objc func openLog() { log("open log"); logQueue.async { DispatchQueue.main.async { NSWorkspace.shared.open(logURL) } } }
}

// MARK: Entry

if CommandLine.arguments.contains("--selftest") {
    precondition(isMCIdentifier("mc.display") && isMCIdentifier("mc.spaces.space.3") && isMCIdentifier("foo.space.12"))
    precondition(!isMCIdentifier("space.3x") && !isMCIdentifier("AXWindow") && !isMCIdentifier("x.space."))
    precondition(shouldCommit(progress: 0.7, commitAt: 0.6) && shouldCommit(progress: -0.7, commitAt: 0.6))
    precondition(!shouldCommit(progress: 0.4, commitAt: 0.6) && !shouldCommit(progress: -0.4, commitAt: 0.6))
    precondition(oneSpaceOffset(spaces: 2) == 2.0 && oneSpaceOffset(spaces: 3) == 1.5 && oneSpaceOffset(spaces: 1) == 2.0)
    print("selftest ok"); exit(0)
}

loadSettings()
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
