//
//  FloatingCodeWindowController.swift
//  MailCode
//
//  Created by MailCode contributors on 2026/6/2.
//

import AppKit
import SwiftUI

@MainActor
final class FloatingCodeWindowController: NSObject, NSWindowDelegate {
    private struct PanelEntry {
        var id: UUID
        var panel: FloatingPanel
    }

    private var panelEntries: [PanelEntry] = []
    private let frameAutosaveKey = "FloatingCodePanelFrame"
    private let panelSize = NSSize(width: 320, height: 228)
    private let panelSpacing: CGFloat = 14

    func show(code: VerificationCode) {
        let id = UUID()
        let panel = makePanel()

        panel.alphaValue = 1
        let hostingView = NSHostingView(
            rootView: FloatingCodeView(code: code) { [weak self] in
                self?.dismiss(id: id)
            }
        )
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        position(panel, at: panelEntries.count)
        panel.orderFrontRegardless()
        panelEntries.append(PanelEntry(id: id, panel: panel))
    }

    func dismiss() {
        panelEntries.map(\.id).forEach { dismiss(id: $0) }
    }

    private func dismiss(id: UUID) {
        guard let index = panelEntries.firstIndex(where: { $0.id == id }) else {
            return
        }

        let entry = panelEntries.remove(at: index)
        saveFrame(for: entry.panel)
        entry.panel.orderOut(nil)
        entry.panel.alphaValue = 1
        restackPanels()
    }

    private func restackPanels() {
        for (index, entry) in panelEntries.enumerated() {
            let targetFrame = frame(forStackIndex: index)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                entry.panel.animator().setFrame(targetFrame, display: true)
            }, completionHandler: {
                entry.panel.contentView?.needsLayout = true
                entry.panel.contentView?.layoutSubtreeIfNeeded()
            })
        }
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: panelSize))
        panel.delegate = self
        return panel
    }

    private func position(_ panel: FloatingPanel, at stackIndex: Int) {
        panel.setFrame(frame(forStackIndex: stackIndex), display: true)
    }

    private func frame(forStackIndex stackIndex: Int) -> NSRect {
        let baseFrame = validBaseFrame()
        let offset = CGFloat(stackIndex) * panelSpacing
        let frame = baseFrame.offsetBy(dx: offset, dy: -offset)
        guard let screenFrame = NSScreen.main?.visibleFrame else {
            return frame
        }

        let x = min(max(frame.minX, screenFrame.minX + 18), screenFrame.maxX - panelSize.width - 18)
        let y = min(max(frame.minY, screenFrame.minY + 18), screenFrame.maxY - panelSize.height - 18)
        return NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height)
    }

    private func validBaseFrame() -> NSRect {
        if let frame = savedFrame(), let screenFrame = NSScreen.main?.visibleFrame,
           screenFrame.intersects(frame) {
            return NSRect(origin: frame.origin, size: panelSize)
        }

        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: screenFrame.maxX - panelSize.width - 28,
            y: screenFrame.minY + 28,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func savedFrame() -> NSRect? {
        guard let value = UserDefaults.standard.string(forKey: frameAutosaveKey) else {
            return nil
        }

        return NSRectFromString(value)
    }

    private func saveFrame(for panel: NSWindow?) {
        guard let panel else {
            return
        }

        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: frameAutosaveKey)
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame(for: notification.object as? NSWindow)
    }
}
