import AppKit
import SwiftUI

enum HUDPosition: String, CaseIterable, Identifiable {
    case topLeft, topCenter, topRight
    case bottomLeft, bottomCenter, bottomRight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topLeft: "Top left"
        case .topCenter: "Top center"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomCenter: "Bottom center"
        case .bottomRight: "Bottom right"
        }
    }
}

/// Borderless, non-activating floating panel hosting HUDView. Draggable
/// anywhere on its body, remembered across launches, visible in every Space.
@MainActor
final class HUDPanelController {
    private var panel: NSPanel?

    func setVisible(_ visible: Bool, store: UsageStore, preferences: Preferences) {
        if visible {
            if panel == nil {
                panel = makePanel(store: store, preferences: preferences)
            }
            ensureOnScreen()
            panel?.orderFrontRegardless()
            // The panel grows once real data lands (SwiftUI resizes it from
            // its bottom-left origin, which can push the top edge past the
            // screen). Re-check after layout settles.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.ensureOnScreen()
            }
        } else {
            panel?.orderOut(nil)
        }
    }

    /// Snap to one of the six anchors. Shows the panel if hidden.
    func apply(positionRaw: String, store: UsageStore, preferences: Preferences) {
        setVisible(true, store: store, preferences: preferences)
        guard let panel, let position = HUDPosition(rawValue: positionRaw) else { return }
        snap(panel, to: position)
        // Re-snap after the content settles at its final height.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let panel = self?.panel else { return }
            self?.snap(panel, to: position)
        }
    }

    private func snap(_ panel: NSPanel, to position: HUDPosition) {
        guard let frame = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame else { return }
        let width = max(panel.frame.width, 316)
        let height = max(panel.frame.height, 130)
        let margin: CGFloat = 16

        let x: CGFloat
        switch position {
        case .topLeft, .bottomLeft: x = frame.minX + margin
        case .topCenter, .bottomCenter: x = frame.midX - width / 2
        case .topRight, .bottomRight: x = frame.maxX - width - margin
        }
        let y: CGFloat
        switch position {
        case .topLeft, .topCenter, .topRight: y = frame.maxY - height - 12
        case .bottomLeft, .bottomCenter, .bottomRight: y = frame.minY + margin
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func makePanel(store: UsageStore, preferences: Preferences) -> NSPanel {
        let hosting = NSHostingController(rootView: HUDView(store: store, preferences: preferences))
        hosting.sizingOptions = [.preferredContentSize]

        // .nonactivatingPanel must be part of the style mask at init time;
        // assigning it afterwards is silently ignored.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 316, height: 170),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        if !panel.setFrameUsingName("HeadroomHUD") {
            snap(panel, to: HUDPosition(rawValue: preferences.hudPositionRaw) ?? .topRight)
        }
        panel.setFrameAutosaveName("HeadroomHUD")
        NSLog("Headroom HUD frame: %@", NSStringFromRect(panel.frame))
        return panel
    }

    /// If the saved position ended up on a disconnected display or partially
    /// off-screen, bring the panel back somewhere fully visible.
    private func ensureOnScreen() {
        guard let panel else { return }
        let contained = NSScreen.screens.contains {
            $0.visibleFrame.insetBy(dx: -8, dy: -8).contains(panel.frame)
        }
        if !contained {
            snap(panel, to: .topRight)
        }
    }
}
