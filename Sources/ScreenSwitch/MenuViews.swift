import AppKit
import ScreenSwitchCore

private let rowWidth: CGFloat = 300
private let inset: CGFloat = 14

/// A display's name with an on/off switch.
@MainActor
final class DisplayRowView: NSView {
    private let onToggle: () -> Void

    init(name: String, isOn: Bool, isEnabled: Bool, onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        super.init(frame: NSRect(x: 0, y: 0, width: rowWidth, height: 30))
        autoresizingMask = .width

        let toggle = NSSwitch()
        toggle.controlSize = .small
        toggle.state = isOn ? .on : .off
        toggle.isEnabled = isEnabled
        toggle.target = self
        toggle.action = #selector(toggled)
        toggle.setAccessibilityLabel(name)
        toggle.sizeToFit()
        toggle.setFrameOrigin(NSPoint(x: rowWidth - inset - toggle.frame.width, y: (30 - toggle.frame.height) / 2))
        toggle.autoresizingMask = .minXMargin

        let label = NSTextField(labelWithString: name)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = isOn ? .labelColor : .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.sizeToFit()
        label.frame = NSRect(
            x: inset, y: (30 - label.frame.height) / 2,
            width: toggle.frame.minX - inset - 8, height: label.frame.height)
        label.autoresizingMask = .width

        addSubview(label)
        addSubview(toggle)
    }

    required init?(coder: NSCoder) { fatalError("not used from a nib") }

    @objc private func toggled() { onToggle() }
}

/// A slider over a display's resolutions. Dragging only updates the label;
/// releasing on a different step commits it, because each change reconfigures
/// the display.
@MainActor
final class ResolutionSliderView: NSView {
    private let steps: [ResolutionStep]
    private let selected: Int
    private let onCommit: (ResolutionStep) -> Void
    private let slider: NSSlider
    private let value = NSTextField(labelWithString: "")

    init(steps: [ResolutionStep], selected: Int, onCommit: @escaping (ResolutionStep) -> Void) {
        self.steps = steps
        self.selected = selected
        self.onCommit = onCommit
        slider = NSSlider(value: Double(selected), minValue: 0, maxValue: Double(max(steps.count - 1, 0)), target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: rowWidth, height: 50))
        autoresizingMask = .width

        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        value.textColor = .secondaryLabelColor
        value.frame = NSRect(x: inset, y: 30, width: rowWidth - 2 * inset, height: 16)
        value.autoresizingMask = .width

        slider.numberOfTickMarks = steps.count
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.isEnabled = steps.count > 1
        slider.target = self
        slider.action = #selector(slid)
        slider.frame = NSRect(x: inset, y: 4, width: rowWidth - 2 * inset, height: 24)
        slider.autoresizingMask = .width

        addSubview(value)
        addSubview(slider)
        showValue(of: selected)
    }

    required init?(coder: NSCoder) { fatalError("not used from a nib") }

    @objc private func slid() {
        let index = slider.integerValue
        showValue(of: index)
        if NSApp.currentEvent?.type == .leftMouseUp, index != selected {
            onCommit(steps[index])
        }
    }

    private func showValue(of index: Int) {
        value.stringValue = steps.indices.contains(index) ? steps[index].title : ""
    }
}
