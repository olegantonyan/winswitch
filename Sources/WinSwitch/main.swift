import AppKit

// `WinSwitch --list` prints the windows the switcher would show on the current desktop and exits.
// Handy for debugging. When run from a terminal, macOS checks the *terminal's* Accessibility
// permission, not WinSwitch's.
if CommandLine.arguments.contains("--list") {
    if !AXIsProcessTrusted() {
        FileHandle.standardError.write(Data("note: no Accessibility permission for this process; list will be empty\n".utf8))
    }
    for w in WindowList.shared.windows(currentDesktopOnly: true) {
        print("\(w.id)\t\(w.appName)\t\(w.title)")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
