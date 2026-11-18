import AppKit
import Carbon.HIToolbox

/// Global keyboard hook (a CGEventTap — think of it as an evdev/XRecord-style grab that can also
/// swallow events). Drives the switcher and records new shortcuts for the settings window.
///
/// The callback runs on the main run loop and must return quickly, or macOS disables the tap;
/// anything slow (listing windows, drawing) is dispatched asynchronously.
final class HotkeyTap {
    private let settings: AppSettings
    private let switcher: Switcher
    private var tap: CFMachPort?
    private var active = false                 // switcher session in progress
    private var swallowedKeyUps = Set<Int64>() // key-ups whose key-down we ate

    init(settings: AppSettings, switcher: Switcher) {
        self.settings = settings
        self.switcher = switcher
    }

    /// Fails until the app has the Accessibility permission.
    func start() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let me = Unmanaged<HotkeyTap>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if consumeKeyDown(Int(keyCode), event) {
                swallowedKeyUps.insert(keyCode)
                return nil
            }
            return pass
        case .keyUp:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            return swallowedKeyUps.remove(keyCode) != nil ? nil : pass
        case .flagsChanged:
            // Hold modifier released → switch to the selected window.
            if active && !event.flags.contains(settings.shortcut.holdModifiers) {
                active = false
                DispatchQueue.main.async { self.switcher.commit() }
            }
            return pass
        default:
            return pass
        }
    }

    /// Returns true when the key press is ours and must not reach the focused app.
    private func consumeKeyDown(_ keyCode: Int, _ event: CGEvent) -> Bool {
        let mods = event.flags.intersection(Shortcut.relevantMask)
        let hold = mods.intersection(Shortcut.holdMask)

        if settings.isRecording {
            if hold.isEmpty {
                // A shortcut needs ⌘/⌥/⌃. Esc cancels; other plain keys are ignored.
                if keyCode == kVK_Escape { DispatchQueue.main.async { self.settings.isRecording = false } }
                return true
            }
            let recorded = Shortcut(keyCode: UInt16(keyCode), modifiers: mods,
                                    keyLabel: Shortcut.label(keyCode: keyCode, event: event))
            DispatchQueue.main.async { self.settings.finishRecording(recorded) }
            return true
        }

        let shortcut = settings.shortcut
        let shiftInShortcut = shortcut.modifiers.contains(.maskShift)
        if keyCode == Int(shortcut.keyCode) && hold == shortcut.holdModifiers
            && (!shiftInShortcut || mods.contains(.maskShift)) {
            let backwards = !shiftInShortcut && mods.contains(.maskShift)
            if active {
                DispatchQueue.main.async { self.switcher.move(backwards ? -1 : 1) }
            } else {
                active = true
                DispatchQueue.main.async { self.switcher.show(reverse: backwards) }
            }
            return true
        }

        guard active else { return false }
        switch keyCode {
        case kVK_Escape:
            active = false
            DispatchQueue.main.async { self.switcher.cancel() }
        case kVK_Return:
            active = false
            DispatchQueue.main.async { self.switcher.commit() }
        case kVK_LeftArrow, kVK_UpArrow:
            DispatchQueue.main.async { self.switcher.move(-1) }
        case kVK_RightArrow, kVK_DownArrow:
            DispatchQueue.main.async { self.switcher.move(1) }
        default:
            break
        }
        return true  // while the switcher is open, keys don't leak into the focused app
    }
}
