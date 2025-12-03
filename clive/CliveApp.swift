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
    var settingsCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        usageManager = UsageManager { [weak self] usage in
            self?.currentUsage = usage
            self?.updateMenuBar(with: usage)
        }
        usageManager?.startPolling()

        // Listen for settings changes
        settingsCancellable = SettingsManager.shared.$displayMode.sink { [weak self] _ in
            self?.updateMenuBar(with: self?.currentUsage)
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

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView()
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 140),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "Clive Settings"
            settingsWindow?.contentView = NSHostingView(rootView: view)
            settingsWindow?.center()
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
