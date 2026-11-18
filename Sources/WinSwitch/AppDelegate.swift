import AppKit
import Combine
import SwiftUI
import os

private let logger = Logger(subsystem: "local.winswitch", category: "app")

/// Logs to the unified log (`/usr/bin/log stream --predicate 'subsystem == "local.winswitch"'`), and to
/// stderr when started from a terminal.
func wsLog(_ message: String) {
    logger.notice("\(message, privacy: .public)")
    if isatty(STDERR_FILENO) != 0 { FileHandle.standardError.write(Data((message + "\n").utf8)) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let settings = AppSettings.shared
    private let switcher = Switcher()
    private lazy var tap = HotkeyTap(settings: settings, switcher: switcher)
    private var statusItem: NSStatusItem!
    private var grantItem: NSMenuItem!
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?
    private var tapRunning = false
    private var hotkeySubscription: AnyCancellable?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        handleTerminationSignals()
        setUpStatusItem()
        settings.setUpLoginItemOnFirstLaunch()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        if !tryStart() {
            // Adds WinSwitch to the Accessibility list and shows the system prompt.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            showSettings()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                if self?.tryStart() ?? true { timer.invalidate() }
            }
        }
    }

    /// Launching the app again (Finder, Dock, Spotlight) while it runs opens Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func tryStart() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        settings.accessibilityGranted = true
        guard tap.start() else {
            wsLog("could not create event tap, will retry")
            return false
        }
        wsLog("event tap active, shortcut \(settings.shortcut.display)")
        tapRunning = true
        // Take ⌘Tab / ⌘` from macOS only while our tap is alive to handle them.
        hotkeySubscription = settings.$shortcut.combineLatest(settings.$isRecording)
            .sink { shortcut, recording in SystemHotkeys.update(for: shortcut, recording: recording) }
        WindowList.shared.refreshCache()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        SystemHotkeys.restore()
    }

    /// `pkill` / Ctrl-C would skip applicationWillTerminate and leave macOS's ⌘Tab switched off.
    private func handleTerminationSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                SystemHotkeys.restore()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    @objc private func activeSpaceChanged() {
        // Let the new desktop settle, then remember its windows for the all-desktops mode.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if AXIsProcessTrusted() { WindowList.shared.refreshCache() }
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "WinSwitch")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        menu.delegate = self
        grantItem = NSMenuItem(title: "Grant Accessibility Access…",
                               action: #selector(openAccessibilitySettings), keyEquivalent: "")
        grantItem.target = self
        menu.addItem(grantItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit WinSwitch", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        grantItem.isHidden = AXIsProcessTrusted()
    }

    // MARK: - Settings window

    @objc func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings) { [weak self] in self?.openAccessibilitySettings() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "WinSwitch Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        settings.accessibilityGranted = AXIsProcessTrusted()
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        settings.isRecording = false
    }

    @objc func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
