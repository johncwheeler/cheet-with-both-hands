import AppKit
import SwiftUI

/// The Cheeter launch splash: fades the character in over the desktop, holds it until the app is
/// ready (and for at least `minimumHold` once it's fully visible), then fades it out.
@MainActor
final class SplashController {
    static let minimumHold: Duration = .milliseconds(500)
    private static let fadeIn: TimeInterval = 0.3
    private static let fadeOut: TimeInterval = 0.4

    private var panel: NSPanel?
    private var holdElapsed = false
    private var isReady = false
    private var isFinished = false
    private var finishActions: [() -> Void] = []

    /// The splash window while it's on screen (for snapshots).
    var window: NSWindow? { panel }

    /// Puts the splash on screen. Returns `nil` when the artwork isn't available.
    static func show(_ image: NSImage?) -> SplashController? {
        guard let image else { return nil }
        let splash = SplashController()
        splash.present(image)
        return splash
    }

    private func present(_ image: NSImage) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let height = min(520, visible.height * 0.6)
        let size = NSSize(width: height * image.size.width / image.size.height, height: height)
        let frame = NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)

        let panel = NSPanel(contentRect: frame.integral, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let hosting = NSHostingView(rootView: SplashView(image: image))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeIn
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.startHold() }
        })
    }

    private func startHold() {
        Task { [weak self] in
            try? await Task.sleep(for: Self.minimumHold)
            self?.holdElapsed = true
            self?.dismissIfDone()
        }
    }

    /// The app has finished starting up; the splash leaves once the minimum hold has passed too.
    func markReady() {
        isReady = true
        dismissIfDone()
    }

    /// Runs `action` once the splash is gone (immediately if it already is).
    func whenFinished(_ action: @escaping () -> Void) {
        if isFinished { action() } else { finishActions.append(action) }
    }

    private func dismissIfDone() {
        guard holdElapsed, isReady, let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.fadeOut
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                guard let self else { return }
                self.isFinished = true
                let actions = self.finishActions
                self.finishActions.removeAll()
                actions.forEach { $0() }
            }
        })
    }
}

private struct SplashView: View {
    let image: NSImage
    @State private var settled = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .scaleEffect(settled ? 1 : 0.94)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { settled = true }
            }
    }
}
