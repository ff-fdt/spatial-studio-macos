import AppKit
import SwiftUI

/// Keep the native slider's hit targets and keyboard handling, without the
/// extra AppKit focus-ring drawing when hosted inside a glass popover.
struct GainSlider: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var label: String

    func makeCoordinator() -> Coordinator { Coordinator($value) }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.focusRingType = .none
        slider.isContinuous = true
        slider.setAccessibilityLabel(label)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        if abs(slider.doubleValue - value) > 0.0001 { slider.doubleValue = value }
    }

    @MainActor
    final class Coordinator: NSObject {
        var value: Binding<Double>
        init(_ value: Binding<Double>) { self.value = value }
        @objc func changed(_ slider: NSSlider) { value.wrappedValue = slider.doubleValue }
    }
}
