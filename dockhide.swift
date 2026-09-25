import Cocoa
import ApplicationServices

// dockhide — hides an app (Cmd+H) when its Dock icon is clicked
// while it is already the active (frontmost) app. A second click shows it
// again via the Dock's standard behavior.
//
// Build:  swiftc -O dockhide.swift -o dockhide
// Run:    ./dockhide   (requires the Accessibility permission)

// --- Accessibility permission check ---
let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
if !AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
    print("Accessibility permission is missing.")
    print("System Settings → Privacy & Security → Accessibility → add dockhide (or the terminal it is launched from), then restart it.")
    exit(1)
}

// --- Exclusions ---
// Apps whose Dock icon click is an action rather than "show my windows":
// dockhide leaves them alone and passes the click to the Dock as usual.
let excludedBundleIDs: Set<String> = [
    "com.hamet.showdesktop",
]

// --- Global state ---
let systemWide = AXUIElementCreateSystemWide()
var eventTap: CFMachPort? = nil
var swallowNextMouseUp = false

// Returns the app whose Dock icon is under `point`, if any
func appUnderDockIcon(at point: CGPoint) -> NSRunningApplication? {
    var elRef: AXUIElement?
    guard AXUIElementCopyElementAtPosition(systemWide,
                                           Float(point.x), Float(point.y),
                                           &elRef) == .success,
          let el = elRef else { return nil }

    // The element must belong to the Dock process
    var pid: pid_t = 0
    guard AXUIElementGetPid(el, &pid) == .success,
          let owner = NSRunningApplication(processIdentifier: pid),
          owner.bundleIdentifier == "com.apple.dock" else { return nil }

    // ...and must be an application icon (not a folder, the Trash, or a separator)
    var subroleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &subroleRef)
    guard (subroleRef as? String) == "AXApplicationDockItem" else { return nil }

    // The app must be running
    var runningRef: CFTypeRef?
    AXUIElementCopyAttributeValue(el, "AXIsApplicationRunning" as CFString, &runningRef)
    guard (runningRef as? NSNumber)?.boolValue == true else { return nil }

    // Icon's bundle URL → match against running applications
    var urlRef: CFTypeRef?
    AXUIElementCopyAttributeValue(el, kAXURLAttribute as CFString, &urlRef)
    guard let nsurl = urlRef as? NSURL else { return nil }
    let iconURL = (nsurl as URL).standardizedFileURL

    return NSWorkspace.shared.runningApplications.first {
        $0.bundleURL?.standardizedFileURL == iconURL
    }
}

// --- Event tap callback ---
func tapCallback(proxy: CGEventTapProxy,
                 type: CGEventType,
                 event: CGEvent,
                 refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        // The system may have disabled the tap — re-enable it
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }

    case .leftMouseUp:
        if swallowNextMouseUp {
            swallowNextMouseUp = false
            return nil
        }

    case .leftMouseDown:
        // Leave modified clicks alone (Ctrl — context menu,
        // Option/Cmd — standard Dock gestures)
        guard event.flags.intersection([.maskCommand, .maskAlternate,
                                        .maskControl, .maskShift]).isEmpty
        else { break }

        if let app = appUnderDockIcon(at: event.location),
           app.isActive, !app.isHidden,
           !excludedBundleIDs.contains(app.bundleIdentifier ?? "") {
            app.hide()
            swallowNextMouseUp = true
            return nil  // don't pass the click to the Dock, or it would re-activate the app right away
        }

    default:
        break
    }
    return Unmanaged.passUnretained(event)
}

// --- Event tap setup ---
let mask: CGEventMask =
    (1 << CGEventType.leftMouseDown.rawValue) |
    (1 << CGEventType.leftMouseUp.rawValue)

eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                             place: .headInsertEventTap,
                             options: .defaultTap,
                             eventsOfInterest: mask,
                             callback: tapCallback,
                             userInfo: nil)

guard let tap = eventTap else {
    print("Failed to create the event tap — check the Accessibility permission.")
    exit(1)
}

let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("dockhide is running: clicking the Dock icon of the active app hides it.")
CFRunLoopRun()
