import AppKit

/// One switching session: the window list, the selection, and the on-screen panel.
final class Switcher {
    private let panel = SwitcherPanel()
    private var items: [WindowItem] = []
    private var selected = 0
    private var pendingShow: DispatchWorkItem?

    func show(reverse: Bool) {
        items = WindowList.shared.windows(currentDesktopOnly: AppSettings.shared.currentDesktopOnly)
        guard !items.isEmpty else { return }
        selected = items.count == 1 ? 0 : (reverse ? items.count - 1 : 1)
        // Show the panel after a short delay, so a quick ⌥Tab flips windows without flashing the list.
        let work = DispatchWorkItem { [weak self] in self?.present() }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selected = ((selected + delta) % items.count + items.count) % items.count
        if panel.isVisible { panel.update(selected: selected) } else { present() }
    }

    func commit() {
        let target = items.indices.contains(selected) ? items[selected] : nil
        close()
        if let target { WindowList.shared.focus(target) }
    }

    func cancel() { close() }

    private func present() {
        pendingShow?.cancel()
        pendingShow = nil
        panel.show(items, selected: selected)
    }

    private func close() {
        pendingShow?.cancel()
        pendingShow = nil
        panel.orderOut(nil)
        items = []
    }
}

/// Borderless, non-activating floating list. It never takes keyboard focus: keys arrive via the
/// event tap, so the app you're switching from stays focused until you pick a window.
final class SwitcherPanel: NSPanel {
    private let width: CGFloat = 560
    private let rowHeight: CGFloat = 32
    private let padding: CGFloat = 8
    private let spacing: CGFloat = 2
    private let stack = NSStackView()
    private var items: [WindowItem] = []
    private var firstVisible = 0
    private var maxRows = 10

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: 12)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.edgeInsets = NSEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        contentView = effect
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ items: [WindowItem], selected: Int) {
        self.items = items
        firstVisible = 0
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        maxRows = max(1, Int((area.height * 0.7 - 2 * padding + spacing) / (rowHeight + spacing)))
        update(selected: selected)

        let rows = CGFloat(min(items.count, maxRows))
        let height = rows * rowHeight + (rows - 1) * spacing + 2 * padding
        setFrame(NSRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height).integral,
                 display: true)
        orderFrontRegardless()
        invalidateShadow()
    }

    /// Redraws the rows, scrolling the visible slice so the selection stays in view.
    func update(selected: Int) {
        let count = min(items.count, maxRows)
        if selected < firstVisible { firstVisible = selected }
        if selected >= firstVisible + count { firstVisible = selected - count + 1 }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for i in firstVisible..<firstVisible + count {
            stack.addArrangedSubview(RowView(item: items[i], selected: i == selected,
                                             width: width - 2 * padding, height: rowHeight))
        }
    }

    private static func roundedMask(radius r: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: r * 2 + 1, height: r * 2 + 1), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }
}

/// App icon + window title + dimmed app name.
private final class RowView: NSView {
    init(item: WindowItem, selected: Bool, width: CGFloat, height: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        if selected { layer?.backgroundColor = NSColor.controlAccentColor.cgColor }

        let icon = NSImageView()
        icon.image = item.icon
        icon.imageScaling = .scaleProportionallyUpOrDown

        let title = NSTextField(labelWithString: item.title)
        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        title.textColor = selected ? .white : .labelColor
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let app = NSTextField(labelWithString: item.appName)
        app.font = .systemFont(ofSize: 11)
        app.textColor = selected ? NSColor.white.withAlphaComponent(0.8) : .secondaryLabelColor
        app.setContentCompressionResistancePriority(.required, for: .horizontal)
        app.setContentHuggingPriority(.required, for: .horizontal)
        app.isHidden = item.title == item.appName

        let row = NSStackView(views: [icon, title, app])
        row.orientation = .horizontal
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: height),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}
