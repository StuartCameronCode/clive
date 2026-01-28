import Foundation

enum DisplayMode: String {
    case text
    case pieChart
    case barChart
}

enum RefreshInterval: Int, CaseIterable {
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    var displayName: String {
        switch self {
        case .oneMinute: return "1 minute"
        case .twoMinutes: return "2 minutes"
        case .fiveMinutes: return "5 minutes"
        case .tenMinutes: return "10 minutes"
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        }
    }
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let displayModeKey = "displayMode"
    private let refreshIntervalKey = "refreshInterval"
    private let claudePathKey = "claudePath"

    static let defaultClaudePath = "/opt/homebrew/bin/claude"

    @Published var displayMode: DisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: displayModeKey)
        }
    }

    @Published var refreshInterval: RefreshInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: refreshIntervalKey)
        }
    }

    @Published var claudePath: String {
        didSet {
            UserDefaults.standard.set(claudePath, forKey: claudePathKey)
        }
    }

    // In-memory log of last raw Claude output (not persisted)
    @Published var lastRawOutput: String = ""

    init() {
        if let saved = UserDefaults.standard.string(forKey: displayModeKey),
           let mode = DisplayMode(rawValue: saved) {
            self.displayMode = mode
        } else {
            self.displayMode = .text
        }

        let savedInterval = UserDefaults.standard.integer(forKey: refreshIntervalKey)
        if savedInterval > 0, let interval = RefreshInterval(rawValue: savedInterval) {
            self.refreshInterval = interval
        } else {
            self.refreshInterval = .fiveMinutes
        }

        if let savedPath = UserDefaults.standard.string(forKey: claudePathKey), !savedPath.isEmpty {
            self.claudePath = savedPath
        } else {
            self.claudePath = SettingsManager.defaultClaudePath
        }
    }
}
