import AppKit
import Observation
import PublishKit

/// One trailing accessory: the gear stays at its original right edge as the reminder grows left.
@MainActor
final class UpdateTitlebarControls: NSView {
    let gear: NSButton
    let reminder = NSButton()
    private let updates: UpdateController?

    init(gear: NSButton, updates: UpdateController?) {
        self.gear = gear
        self.updates = updates
        super.init(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        addSubview(gear)
        reminder.isBordered = false
        reminder.target = self
        reminder.action = #selector(showUpdate)
        reminder.toolTip = "查看墨驿软件更新"
        reminder.wantsLayer = true
        reminder.layer?.cornerRadius = 5
        reminder.layer?.borderWidth = 1
        reminder.layer?.borderColor = NSColor(srgbRed: 204/255, green: 214/255, blue: 192/255, alpha: 1).cgColor
        addSubview(reminder)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func refresh() {
        let label: String? = withObservationTracking {
            guard let state = updates?.state, state.hasReminder else { return nil }
            if state.phase == .available { return "有更新" }
            if state.phase == .downloading {
                return state.progress.map { "下载中 \(Int($0 * 100))%" } ?? "下载中"
            }
            return "查看更新"
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        let green = NSColor(srgbRed: 80/255, green: 102/255, blue: 75/255, alpha: 1)
        let title = NSMutableAttributedString()
        if label == "有更新" {
            title.append(NSAttributedString(string: "●", attributes: [
                .font: NSFont.systemFont(ofSize: 4), .foregroundColor: green, .baselineOffset: 2
            ]))
            title.append(NSAttributedString(string: " ", attributes: [.font: NSFont.systemFont(ofSize: 10)]))
        }
        title.append(NSAttributedString(string: label ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: green
        ]))
        reminder.attributedTitle = title
        reminder.setAccessibilityLabel(label)
        reminder.isHidden = label == nil
        let reminderWidth = label == nil ? 0 : ceil(title.size().width) + 14
        let width = 36 + (label == nil ? 0 : reminderWidth + 8)
        setFrameSize(NSSize(width: width, height: 28))
        gear.frame = NSRect(x: width - 36, y: 0, width: 36, height: 28)
        reminder.frame = NSRect(x: 0, y: 2, width: reminderWidth, height: 24)
        invalidateIntrinsicContentSize()
    }
    override var intrinsicContentSize: NSSize { frame.size }
    @objc private func showUpdate() { updates?.show() }
}
