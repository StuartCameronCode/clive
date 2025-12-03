import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared

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
        }
        .padding(20)
        .frame(width: 280, height: 140)
    }
}
