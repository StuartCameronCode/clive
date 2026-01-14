import SwiftUI
import Combine

@main
struct ClaudeUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var usageManager: UsageManager?
    var settingsWindow: NSWindow?
    var currentUsage: UsageInfo?
    var currentError: UsageError?
    var settingsCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        usageManager = UsageManager(
            onUpdate: { [weak self] usage in
                self?.currentUsage = usage
                self?.updateMenuBar(with: usage)
            },
            onError: { [weak self] error in
                self?.currentError = error
                self?.updateMenuBarForError(error)
            }
        )
        usageManager?.startPolling()

        // Listen for settings changes
        settingsCancellable = SettingsManager.shared.$displayMode.sink { [weak self] _ in
            if self?.currentError != nil {
                self?.updateMenuBarForError(self?.currentError)
            } else {
                self?.updateMenuBar(with: self?.currentUsage)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageManager?.stopPolling()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.title = "CC: --"
        }

        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()

        let errorItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        errorItem.isEnabled = false
        errorItem.tag = 99
        errorItem.isHidden = true
        menu.addItem(errorItem)

        let sessionItem = NSMenuItem(title: "Session: --", action: nil, keyEquivalent: "")
        sessionItem.isEnabled = false
        sessionItem.tag = 100
        menu.addItem(sessionItem)

        let weeklyItem = NSMenuItem(title: "Weekly: --", action: nil, keyEquivalent: "")
        weeklyItem.isEnabled = false
        weeklyItem.tag = 101
        menu.addItem(weeklyItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    private func updateUsageMenuItem() {
        guard let menu = statusItem?.menu,
              let sessionItem = menu.item(withTag: 100),
              let weeklyItem = menu.item(withTag: 101) else { return }

        let session = currentUsage?.sessionPercent ?? "--"
        let weekly = currentUsage?.weeklyPercent ?? "--"

        if let resets = currentUsage?.sessionResets {
            sessionItem.title = "Session: \(session) (resets \(resets))"
        } else {
            sessionItem.title = "Session: \(session)"
        }
        weeklyItem.title = "Weekly: \(weekly)"
    }

    private func updateMenuBar(with usage: UsageInfo?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem?.button else { return }

            let settings = SettingsManager.shared

            let sessionValue = self.parsePercent(usage?.sessionPercent)
            let weeklyValue = self.parsePercent(usage?.weeklyPercent)

            // Update menu item with percentages
            self.updateUsageMenuItem()

            switch settings.displayMode {
            case .pieChart:
                let image = PieChartRenderer.createImage(sessionPercent: sessionValue, weeklyPercent: weeklyValue)
                image.isTemplate = false
                button.image = image
                button.title = "CC:"
                button.imagePosition = .imageRight
            case .barChart:
                let image = BarChartRenderer.createImage(sessionPercent: sessionValue, weeklyPercent: weeklyValue)
                image.isTemplate = false
                button.image = image
                button.title = "CC:"
                button.imagePosition = .imageRight
            case .text:
                button.image = nil
                button.imagePosition = .noImage
                if let usage = usage {
                    button.title = "CC: \(usage.displayString)"
                } else {
                    button.title = "CC: --"
                }
            }
        }
    }

    private func parsePercent(_ str: String?) -> Double? {
        guard let str = str else { return nil }
        let numStr = str.replacingOccurrences(of: "%", with: "")
        return Double(numStr)
    }

    private func updateMenuBarForError(_ error: UsageError?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem?.button else { return }

            // Update error menu item
            if let menu = self.statusItem?.menu, let errorItem = menu.item(withTag: 99) {
                if let error = error {
                    errorItem.title = error.message
                    errorItem.isHidden = false
                } else {
                    errorItem.title = ""
                    errorItem.isHidden = true
                }
            }

            if error != nil {
                // Show error state with warning icon
                let image = self.createErrorIcon()
                image.isTemplate = false
                button.image = image
                button.title = "CC:"
                button.imagePosition = .imageRight

                // Also clear the usage display items
                if let menu = self.statusItem?.menu,
                   let sessionItem = menu.item(withTag: 100),
                   let weeklyItem = menu.item(withTag: 101) {
                    sessionItem.title = "Session: --"
                    weeklyItem.title = "Weekly: --"
                }
            } else {
                // Error cleared, restore normal display
                self.currentError = nil
                self.updateMenuBar(with: self.currentUsage)
            }
        }
    }

    private func createErrorIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw warning triangle with exclamation mark
            let warningColor = NSColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)

            // Use SF Symbol if available
            if let symbolImage = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error") {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                let configuredImage = symbolImage.withSymbolConfiguration(config)

                // Draw with tint color
                warningColor.set()
                let imageRect = NSRect(x: (rect.width - 16) / 2, y: (rect.height - 16) / 2, width: 16, height: 16)
                configuredImage?.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)

                // Apply color tint by drawing over
                NSGraphicsContext.current?.cgContext.setBlendMode(.sourceAtop)
                warningColor.setFill()
                imageRect.fill()
            }
            return true
        }
        return image
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Clive Settings"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false

            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.settingsWindow = nil
            }

            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func refreshNow() {
        usageManager?.refreshNow()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}
