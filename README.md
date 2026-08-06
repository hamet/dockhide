# dockhide

Hide an active app by clicking its icon in the Dock on macOS.

macOS has no built-in setting for "click the icon of the frontmost app to hide it" — this small Swift utility adds that behavior. Clicking the Dock icon of an app that is already active hides it (the equivalent of Cmd+H). Clicking again shows it back via the Dock's standard behavior.

## How it works

The utility installs a `CGEventTap` on mouse clicks. On each click it uses the Accessibility API to check whether the cursor landed on a Dock element with the subrole `AXApplicationDockItem`, matches the item's bundle URL against the running applications, and — if that app is already active and not hidden — calls `NSRunningApplication.hide()` and swallows the click event (otherwise the Dock would immediately activate the app again).

Clicks with modifier keys (Ctrl, Option, Cmd, Shift) are passed through untouched, so the context menu and the Dock's standard gestures keep working as usual.

## Installation

```bash
swiftc -O dockhide.swift -o dockhide        # requires Xcode CLT: xcode-select --install
sudo mv dockhide /usr/local/bin/
/usr/local/bin/dockhide                     # first run triggers the permission prompt
```

On first launch, macOS will ask for permission under **System Settings → Privacy & Security → Accessibility** — add the `dockhide` binary itself (or the terminal it was launched from), then restart the utility.

## Run at login

Copy the LaunchAgent plist and load it:

```bash
cp com.user.dockhide.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.dockhide.plist
```

## Notes

- `hide()` is exactly Cmd+H (hides all windows of the app), not minimizing a single window to the Dock. If you want "minimize the window" behavior (Cmd+M) instead, replace `app.hide()` with sending `AXPress` to the app's windows.
- For reference: macOS already ships a similar effect out of the box — Option+click on a Dock icon hides the *previous* app. But "second click hides" without modifiers is not something the system can do natively.
