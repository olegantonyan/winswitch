import AppKit
import Carbon.HIToolbox
import ServiceManagement

/// A key + modifiers combo. The ⌘/⌥/⌃ part is the "hold" modifier: releasing it ends the switch.
struct Shortcut: Equatable {
    var keyCode: UInt16
    var modifiers: CGEventFlags
    var keyLabel: String

    /// ⌘Tab: on PC-style keyboards the key labeled "Alt" sends ⌘, so this is the familiar Alt+Tab.
    static let `default` = Shortcut(keyCode: UInt16(kVK_Tab), modifiers: .maskCommand, keyLabel: "⇥")

    /// Modifiers we care about (everything else in CGEventFlags is noise like caps lock / fn).
    static let relevantMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    /// Modifiers that can be "held" for the switcher.
    static let holdMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]

    var holdModifiers: CGEventFlags { modifiers.intersection(Shortcut.holdMask) }

    /// e.g. "⌥⇥", in Apple's standard ⌃⌥⇧⌘ order.
    var display: String {
        var s = ""
        if modifiers.contains(.maskControl) { s += "⌃" }
        if modifiers.contains(.maskAlternate) { s += "⌥" }
        if modifiers.contains(.maskShift) { s += "⇧" }
        if modifiers.contains(.maskCommand) { s += "⌘" }
        return s + keyLabel
    }

    static func label(keyCode: Int, event: CGEvent) -> String {
        let names: [Int: String] = [
            kVK_Tab: "⇥", kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋", kVK_Delete: "⌫",
            kVK_ANSI_Grave: "`", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        ]
        if let name = names[keyCode] { return name }
        let chars = NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? ""
        return chars.isEmpty ? "Key \(keyCode)" : chars.uppercased()
    }
}

/// User settings, persisted in UserDefaults (`defaults read local.winswitch`).
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var shortcut: Shortcut { didSet { saveShortcut() } }
    @Published var currentDesktopOnly: Bool {
        didSet { defaults.set(currentDesktopOnly, forKey: "currentDesktopOnly") }
    }
    @Published var launchAtLogin: Bool { didSet { if !syncingLoginItem { applyLoginItem() } } }

    // Runtime state shown in the settings window (not persisted).
    @Published var isRecording = false
    @Published var note: String?
    @Published var accessibilityGranted = AXIsProcessTrusted()

    private var syncingLoginItem = false

    private init() {
        if defaults.object(forKey: "shortcut.keyCode") != nil {
            shortcut = Shortcut(
                keyCode: UInt16(defaults.integer(forKey: "shortcut.keyCode")),
                modifiers: CGEventFlags(rawValue: UInt64(defaults.integer(forKey: "shortcut.modifiers"))),
                keyLabel: defaults.string(forKey: "shortcut.label") ?? "?")
        } else {
            shortcut = .default
        }
        currentDesktopOnly = defaults.object(forKey: "currentDesktopOnly") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func finishRecording(_ recorded: Shortcut) {
        isRecording = false
        note = nil
        shortcut = recorded
    }

    /// "Start at login" defaults to on, but only for the installed copy in /Applications
    /// (not for `make run` out of the build folder).
    func setUpLoginItemOnFirstLaunch() {
        guard !defaults.bool(forKey: "loginItemConfigured"),
              Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        defaults.set(true, forKey: "loginItemConfigured")
        launchAtLogin = true
    }

    private func saveShortcut() {
        defaults.set(Int(shortcut.keyCode), forKey: "shortcut.keyCode")
        defaults.set(Int(shortcut.modifiers.rawValue), forKey: "shortcut.modifiers")
        defaults.set(shortcut.keyLabel, forKey: "shortcut.label")
    }

    /// Registers/unregisters the app in System Settings → General → Login Items.
    private func applyLoginItem() {
        let service = SMAppService.mainApp
        do {
            if launchAtLogin {
                if service.status != .enabled { try service.register() }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            wsLog("login item: \(error.localizedDescription)")
        }
        if launchAtLogin && service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        // Reflect what macOS actually did.
        syncingLoginItem = true
        launchAtLogin = service.status == .enabled
        syncingLoginItem = false
    }
}
