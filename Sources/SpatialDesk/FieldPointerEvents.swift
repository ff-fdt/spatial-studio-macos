import AppKit
import SwiftUI

/// Handles zoom and contextual clicks within this scene.
struct FieldPointerEvents: NSViewRepresentable {
    var onZoom: (Double, CGPoint) -> Void
    var contextMenu: (CGPoint) -> NSMenu?

    func makeNSView(context: Context) -> View {
        let view = View()
        view.onZoom = onZoom
        view.contextMenu = contextMenu
        return view
    }

    func updateNSView(_ nsView: View, context: Context) {
        nsView.onZoom = onZoom
        nsView.contextMenu = contextMenu
    }

    static func dismantleNSView(_ nsView: View, coordinator: ()) {
        nsView.removeMonitor()
    }

    final class View: NSView {
        var onZoom: ((Double, CGPoint) -> Void)?
        var contextMenu: ((CGPoint) -> NSMenu?)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify, .rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, let window = self.window, window === event.window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                let canvasPoint = CGPoint(x: point.x - self.bounds.minX, y: self.bounds.maxY - point.y)
                switch event.type {
                case .rightMouseDown, .leftMouseDown:
                    guard event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                          let menu = self.contextMenu?(
                            CGPoint(x: point.x - self.bounds.minX, y: self.bounds.maxY - point.y)
                          ) else { return event }
                    NSMenu.popUpContextMenu(menu, with: event, for: self)
                case .scrollWheel:
                    guard event.scrollingDeltaY != 0, event.momentumPhase.isEmpty else { return event }
                    let scale = event.hasPreciseScrollingDeltas ? 0.005 : 0.12
                    self.onZoom?(exp(max(-0.24, min(0.24, event.scrollingDeltaY * scale))), canvasPoint)
                case .magnify:
                    self.onZoom?(max(0.5, 1 + event.magnification), canvasPoint)
                default: return event
                }
                return nil
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
