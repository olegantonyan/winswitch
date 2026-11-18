import AppKit
import ApplicationServices

/// Private but long-stable API (used by AltTab, Hammerspoon, yabai): maps an Accessibility window
/// element to its CoreGraphics window id, so the two window lists can be joined.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

struct WindowItem {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let appName: String
    let icon: NSImage?
    let element: AXUIElement
}

/// Enumerates switchable windows.
///
/// - CoreGraphics gives the window list in front-to-back order (≈ most recently used) and tells
///   which windows are on the current desktop. It needs no permission as long as we don't read
///   window titles from it (that would require Screen Recording).
/// - Accessibility gives titles and lets us raise a specific window.
///
/// Accessibility only reports windows on the *current* desktop, so for the "all desktops" mode we
/// remember elements of windows seen on desktops visited while WinSwitch runs.
final class WindowList {
    static let shared = WindowList()

    private var cache: [CGWindowID: AXUIElement] = [:]
    private let ownPid = ProcessInfo.processInfo.processIdentifier

    func windows(currentDesktopOnly: Bool) -> [WindowItem] {
        var apps: [pid_t: NSRunningApplication] = [:]
        func regularApp(_ pid: pid_t) -> NSRunningApplication? {
            if apps[pid] == nil { apps[pid] = NSRunningApplication(processIdentifier: pid) }
            guard let app = apps[pid], app.activationPolicy == .regular, !app.isHidden else { return nil }
            return app
        }

        // 1. Windows on the current desktop, with fresh Accessibility elements.
        var result: [WindowItem] = []
        var axByPid: [pid_t: [CGWindowID: AXUIElement]] = [:]
        for (id, pid) in candidates([.optionOnScreenOnly, .excludeDesktopElements]) {
            guard let app = regularApp(pid) else { continue }
            if axByPid[pid] == nil { axByPid[pid] = axWindows(pid: pid) }
            guard let element = axByPid[pid]?[id] else { continue }
            cache[id] = element
            result.append(item(id: id, pid: pid, element: element, app: app))
        }
        if currentDesktopOnly { return result }

        // 2. Windows on other desktops that we've seen before and that still exist.
        let shown = Set(result.map(\.id))
        let alive = candidates([.optionAll, .excludeDesktopElements])
        let aliveIds = Set(alive.map(\.0))
        cache = cache.filter { aliveIds.contains($0.key) }
        for (id, pid) in alive where !shown.contains(id) {
            guard let element = cache[id], let app = regularApp(pid),
                  !boolAttribute(element, kAXMinimizedAttribute) else { continue }
            result.append(item(id: id, pid: pid, element: element, app: app))
        }
        return result
    }

    /// Remember the current desktop's windows (called when the desktop changes).
    func refreshCache() {
        _ = windows(currentDesktopOnly: true)
    }

    func focus(_ window: WindowItem) {
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        let app = AXUIElementCreateApplication(window.pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
    }

    // MARK: - Helpers

    /// Normal-looking windows of other processes, front to back.
    private func candidates(_ options: CGWindowListOption) -> [(CGWindowID, pid_t)] {
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid != ownPid,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 50, bounds.height >= 50
            else { return nil }
            return (id, pid)
        }
    }

    private func axWindows(pid: pid_t) -> [CGWindowID: AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)  // don't hang on a frozen app
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else { return [:] }
        var out: [CGWindowID: AXUIElement] = [:]
        for element in elements {
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(element, &id) == .success, id != 0 { out[id] = element }
        }
        return out
    }

    private func item(id: CGWindowID, pid: pid_t, element: AXUIElement, app: NSRunningApplication) -> WindowItem {
        let appName = app.localizedName ?? "?"
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
        let title = (value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? appName
        return WindowItem(id: id, pid: pid, title: title, appName: appName, icon: app.icon, element: element)
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (value as? Bool) ?? false
    }
}
