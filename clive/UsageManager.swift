import Foundation
import Combine

struct UsageInfo {
    let sessionPercent: String?
    let weeklyPercent: String?
    let sessionResets: String?

    var displayString: String {
        let session = sessionPercent ?? "--"
        let weekly = weeklyPercent ?? "--"
        return "\(session) (\(weekly) weekly)"
    }
}

class UsageManager {
    private var refreshTimer: Timer?
    private let onUpdate: (UsageInfo?) -> Void
    private var process: Process?
    private var outputPipe: Pipe?
    private var timeoutTimer: Timer?
    private var isRefreshing = false
    private var settingsCancellable: AnyCancellable?

    private let timeout: TimeInterval = 30

    init(onUpdate: @escaping (UsageInfo?) -> Void) {
        self.onUpdate = onUpdate

        // Listen for refresh interval changes
        settingsCancellable = SettingsManager.shared.$refreshInterval.sink { [weak self] _ in
            self?.restartTimer()
        }
    }

    func startPolling() {
        refreshNow()
        startTimer()
    }

    func stopPolling() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        terminateProcess()
    }

    func refreshNow() {
        guard !isRefreshing else { return }
        performRefresh()
    }

    private func startTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(SettingsManager.shared.refreshInterval.rawValue)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshNow()
        }
    }

    private func restartTimer() {
        if refreshTimer != nil {
            startTimer()
        }
    }

    private func performRefresh() {
        isRefreshing = true

        let proc = Process()
        let pipe = Pipe()

        // Create isolated temp directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-usage-bar")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        proc.currentDirectoryURL = tempDir

        // Write expect script to temp directory
        let expectScript = """
            #!/usr/bin/expect -f
            log_user 1
            set timeout 25
            spawn /opt/homebrew/bin/claude /usage

            # Handle trust dialog if it appears, then read output
            expect {
                "trust" {
                    sleep 0.5
                    send "\\r"
                    exp_continue
                }
                -re "Current week.*\\n.*\\d+%" {
                    # Got the data we need
                }
                timeout {
                    exit 1
                }
                eof { }
            }

            # Give it a moment to finish output
            sleep 1
            """
        let scriptPath = tempDir.appendingPathComponent("claude_usage.exp")
        try? FileManager.default.removeItem(at: scriptPath)
        try? expectScript.write(to: scriptPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

        proc.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
        proc.arguments = ["-f", scriptPath.path]
        proc.standardOutput = pipe
        proc.standardError = pipe

        // Minimal environment
        var env: [String: String] = [:]
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["HOME"] = ProcessInfo.processInfo.environment["HOME"] ?? ""
        env["USER"] = ProcessInfo.processInfo.environment["USER"] ?? ""
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        proc.environment = env

        self.process = proc
        self.outputPipe = pipe

        var accumulatedOutput = ""
        var hasCompleted = false

        // Set up async reading of output
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let str = String(data: data, encoding: .utf8) {
                    accumulatedOutput += str

                    // Check if we have complete data - terminate early if so
                    if !hasCompleted, let usage = parseUsageOutput(accumulatedOutput),
                       usage.sessionPercent != nil && usage.weeklyPercent != nil {
                        hasCompleted = true
                        DispatchQueue.main.async {
                            fileHandle.readabilityHandler = nil
                            self?.timeoutTimer?.invalidate()
                            self?.timeoutTimer = nil
                            self?.handleRefreshComplete(output: accumulatedOutput)
                        }
                    }
                }
            }
        }

        // Handle process termination (fallback if early completion didn't trigger)
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard !hasCompleted else { return }
                hasCompleted = true
                fileHandle.readabilityHandler = nil
                self?.timeoutTimer?.invalidate()
                self?.timeoutTimer = nil
                self?.handleRefreshComplete(output: accumulatedOutput)
            }
        }

        // Set timeout
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.handleTimeout()
        }

        do {
            try proc.run()
        } catch {
            isRefreshing = false
            onUpdate(nil)
        }
    }

    private func handleRefreshComplete(output: String) {
        terminateProcess()

        let usageInfo = parseUsageOutput(output)
        isRefreshing = false

        DispatchQueue.main.async { [weak self] in
            self?.onUpdate(usageInfo)
        }
    }

    private func handleTimeout() {
        terminateProcess()
        isRefreshing = false
        // Don't update UI on timeout, keep showing last known values
    }

    private func terminateProcess() {
        if let process = process, process.isRunning {
            process.terminate()
        }
        process = nil
        outputPipe = nil
    }
}

func parseUsageOutput(_ output: String) -> UsageInfo? {
    guard !output.isEmpty else { return nil }

    var sessionPercent: String?
    var weeklyPercent: String?
    var sessionResets: String?

    // Find the LAST occurrence of each section to get most recent values
    if let lastSessionRange = output.range(of: "Current session", options: .backwards) {
        let afterSession = output[lastSessionRange.upperBound...]
        // Find next section or end
        let endRange = afterSession.range(of: "Current week") ?? afterSession.endIndex..<afterSession.endIndex
        let sessionSection = afterSession[..<endRange.lowerBound]
        if let match = sessionSection.range(of: #"\d+%"#, options: .regularExpression) {
            sessionPercent = String(sessionSection[match])
        }
        // Extract reset time (e.g., "Resets 3pm (Australia/Melbourne)")
        if let resetMatch = sessionSection.range(of: #"Resets [^(\n]+"#, options: .regularExpression) {
            let resetStr = String(sessionSection[resetMatch])
            // Extract just the time part after "Resets "
            sessionResets = String(resetStr.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
    }

    if let lastWeeklyRange = output.range(of: "Current week", options: .backwards) {
        let afterWeekly = output[lastWeeklyRange.upperBound...]
        if let match = afterWeekly.range(of: #"\d+%"#, options: .regularExpression) {
            weeklyPercent = String(afterWeekly[match])
        }
    }

    guard sessionPercent != nil || weeklyPercent != nil else { return nil }

    return UsageInfo(
        sessionPercent: sessionPercent,
        weeklyPercent: weeklyPercent,
        sessionResets: sessionResets
    )
}
