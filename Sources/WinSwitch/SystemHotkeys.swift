import Carbon.HIToolbox
import CoreGraphics

/// Private but long-stable API (AltTab uses it the same way): toggles macOS's built-in
/// "symbolic hotkeys". ⌘Tab / ⌘` are handled by the system before any event tap sees them, so to
/// use them as WinSwitch's shortcut, the built-in ones must be switched off while WinSwitch runs.
@_silgen_name("CGSSetSymbolicHotKeyEnabled")
private func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ enabled: Bool) -> CGError

enum SystemHotkeys {
    private static let commandTab: Int32 = 1          // ⌘Tab app switcher
    private static let commandShiftTab: Int32 = 2     // ⌘⇧Tab
    private static let commandKeyAboveTab: Int32 = 6  // ⌘` cycle app windows
    private static var graveDisabledByUs = false

    /// Hand ⌘Tab (and ⌘`) to WinSwitch when the shortcut uses them, or while recording a new one.
    static func update(for shortcut: Shortcut?, recording: Bool) {
        let isCommandOnly = shortcut?.holdModifiers == .maskCommand
        let takeTab = recording || (isCommandOnly && shortcut?.keyCode == UInt16(kVK_Tab))
        let takeGrave = recording || (isCommandOnly && shortcut?.keyCode == UInt16(kVK_ANSI_Grave))

        // ⌘Tab can't be turned off in System Settings, so always setting it explicitly is safe;
        // it also repairs the state if a previous run crashed while holding it.
        _ = CGSSetSymbolicHotKeyEnabled(commandTab, !takeTab)
        _ = CGSSetSymbolicHotKeyEnabled(commandShiftTab, !takeTab)
        // ⌘` can be turned off by the user, so only touch it when we need it or took it earlier.
        if takeGrave || graveDisabledByUs {
            _ = CGSSetSymbolicHotKeyEnabled(commandKeyAboveTab, !takeGrave)
            graveDisabledByUs = takeGrave
        }
    }

    /// Give everything back to macOS (on quit).
    static func restore() {
        update(for: nil, recording: false)
    }
}
