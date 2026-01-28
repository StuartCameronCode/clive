import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var isPathValid: Bool = true
    @State private var showingAbout: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Display Mode", selection: $settings.displayMode) {
                    Text("Text").tag(DisplayMode.text)
                    Text("Pie Charts").tag(DisplayMode.pieChart)
                    Text("Bar Chart").tag(DisplayMode.barChart)
                }
                .pickerStyle(.radioGroup)

                Picker("Refresh Interval", selection: $settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases, id: \.self) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .pickerStyle(.menu)

                Divider()
                    .padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Claude Executable Path")
                        .font(.headline)

                    HStack {
                        TextField("Path to claude", text: $settings.claudePath)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: settings.claudePath) { newValue in
                                isPathValid = FileManager.default.isExecutableFile(atPath: newValue)
                            }

                        Button("Browse...") {
                            selectClaudePath()
                        }
                    }

                    if !isPathValid && !settings.claudePath.isEmpty {
                        Text("Executable not found at this path")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Button("Reset to Default") {
                        settings.claudePath = SettingsManager.defaultClaudePath
                        isPathValid = FileManager.default.isExecutableFile(atPath: settings.claudePath)
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .padding(20)

            Spacer()

            HStack {
                Button("Show Log") {
                    openLogWindow()
                }

                Spacer()

                Button("About") {
                    showingAbout = true
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 400, height: 320)
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .onAppear {
            isPathValid = FileManager.default.isExecutableFile(atPath: settings.claudePath)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        #if DEBUG
        return "\(version)-DEBUG"
        #else
        return version
        #endif
    }

    private func selectClaudePath() {
        let panel = NSOpenPanel()
        panel.title = "Select Claude Executable"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/opt/homebrew/bin")

        if panel.runModal() == .OK, let url = panel.url {
            settings.claudePath = url.path
            isPathValid = FileManager.default.isExecutableFile(atPath: settings.claudePath)
        }
    }

    private func openLogWindow() {
        let logView = LogView(output: settings.lastRawOutput)
        let hostingView = NSHostingView(rootView: logView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Output Log"
        window.contentView = hostingView
        window.contentMinSize = NSSize(width: 500, height: 300)
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        LogWindowManager.shared.addWindow(controller)
    }
}

/// Manages log window lifecycle to prevent app from quitting when windows close
class LogWindowManager {
    static let shared = LogWindowManager()
    private var windowControllers: [NSWindowController] = []

    func addWindow(_ controller: NSWindowController) {
        windowControllers.append(controller)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: controller.window,
            queue: .main
        ) { [weak self] notification in
            if let window = notification.object as? NSWindow {
                self?.windowControllers.removeAll { $0.window === window }
            }
        }
    }
}

struct LogView: View {
    let output: String

    var body: some View {
        VStack(spacing: 0) {
            if output.isEmpty {
                VStack {
                    Spacer()
                    Text("No output captured yet")
                        .foregroundColor(.secondary)
                    Text("Output will appear after the next refresh")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                HStack {
                    Spacer()
                    Button("Copy to Clipboard") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(output, forType: .string)
                    }
                }
                .padding([.top, .trailing])

                ScrollView {
                    Text(output)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        #if DEBUG
        return "\(version)-DEBUG"
        #else
        return version
        #endif
    }

    var body: some View {
        VStack(spacing: 16) {
            // App icon and name
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            Text("Clive")
                .font(.title)
                .fontWeight(.bold)

            Text("Version \(appVersion)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()
                .padding(.horizontal, 40)

            // Author and project link
            VStack(spacing: 8) {
                Text("Created by Stuart Cameron")
                    .font(.body)

                Link("github.com/StuartCameronCode/clive",
                     destination: URL(string: "https://github.com/StuartCameronCode/clive")!)
                    .font(.body)
            }

            Divider()
                .padding(.horizontal, 40)

            // License
            VStack(spacing: 8) {
                Text("Released under the MIT License")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Divider()
                .padding(.horizontal, 40)

            // Third-party libraries
            VStack(spacing: 4) {
                Text("Third-Party Libraries")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack(spacing: 4) {
                    Text("Terminal rendering powered by")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Link("SwiftTerm",
                         destination: URL(string: "https://github.com/migueldeicaza/SwiftTerm")!)
                        .font(.caption)
                }
            }

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .fixedSize()
    }
}
