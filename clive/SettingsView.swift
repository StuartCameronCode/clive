import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var isPathValid: Bool = true

    var body: some View {
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

            Spacer()

            HStack {
                Spacer()
                Text("Version \(appVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 400, height: 300)
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
}
