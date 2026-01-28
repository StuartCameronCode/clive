import Foundation
import Combine
import SwiftTerm

struct UsageInfo {
    let sessionPercent: String?
    let weeklyPercent: String?
    let sessionResets: String?
    let weeklyResets: String?

    var displayString: String {
        let session = sessionPercent ?? "--"
        let weekly = weeklyPercent ?? "--"
        return "\(session) (\(weekly) weekly)"
    }
}

enum UsageError {
    case executableNotFound(path: String)
    case launchFailed(error: String)

    var message: String {
        switch self {
        case .executableNotFound(let path):
            return "Claude not found at: \(path)"
        case .launchFailed(let error):
            return "Failed to launch Claude: \(error)"
        }
    }
}

class UsageManager {
    private var refreshTimer: Timer?
    private let onUpdate: (UsageInfo?) -> Void
    private let onError: (UsageError?) -> Void
    private var process: Process?
    private var outputPipe: Pipe?
    private var timeoutTimer: Timer?
    private var isRefreshing = false
    private var settingsCancellables = Set<AnyCancellable>()

    private let timeout: TimeInterval = 30

    init(onUpdate: @escaping (UsageInfo?) -> Void, onError: @escaping (UsageError?) -> Void) {
        self.onUpdate = onUpdate
        self.onError = onError

        // Listen for refresh interval changes
        SettingsManager.shared.$refreshInterval.sink { [weak self] _ in
            self?.restartTimer()
        }.store(in: &settingsCancellables)

        // Listen for claude path changes and refresh when changed
        SettingsManager.shared.$claudePath.sink { [weak self] _ in
            self?.refreshNow()
        }.store(in: &settingsCancellables)
    }

    private func checkExecutableExists() -> Bool {
        let path = SettingsManager.shared.claudePath
        return FileManager.default.isExecutableFile(atPath: path)
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

        let claudePath = SettingsManager.shared.claudePath

        // Check if executable exists
        guard checkExecutableExists() else {
            isRefreshing = false
            onError(.executableNotFound(path: claudePath))
            return
        }

        // Clear any previous error on successful check
        onError(nil)

        let proc = Process()
        let pipe = Pipe()

        // Create isolated temp directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-usage-bar")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        proc.currentDirectoryURL = tempDir

        // Get directory containing claude for PATH
        let claudeDir = (claudePath as NSString).deletingLastPathComponent

        // Write expect script to temp directory
        let expectScript = """
            #!/usr/bin/expect -f
            log_user 1
            set timeout 25
            spawn \(claudePath) /usage

            # Handle trust dialog if it appears, then read output
            expect {
                "trust" {
                    sleep 0.5
                    send "\\r"
                    exp_continue
                }
                -re "Current week \\(all models\\).*\\n.*\\d+%" {
                    # Got the data we need (all models stat)
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

        // Minimal environment - include claude's directory in PATH
        var env: [String: String] = [:]
        env["PATH"] = "\(claudeDir):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
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
            onError(.launchFailed(error: error.localizedDescription))
        }
    }

    private func handleRefreshComplete(output: String) {
        terminateProcess()

        // Write raw binary output to file for debugging
        let debugPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("clive-raw-output.bin")
        try? output.data(using: .utf8)?.write(to: debugPath)

        let usageInfo = parseUsageOutput(output)
        isRefreshing = false

        DispatchQueue.main.async { [weak self] in
            // Store rendered output for debugging
            SettingsManager.shared.lastRawOutput = renderAnsiOutput(output)
            self?.onUpdate(usageInfo)
        }
    }

    private func handleTimeout() {
        terminateProcess()
        isRefreshing = false
        // Don't update UI on timeout, keep showing last known values
    }

    private func terminateProcess() {
        if let proc = process {
            let pid = proc.processIdentifier
            if proc.isRunning {
                // Kill the entire process tree (expect + spawned claude process)
                // First try to kill child processes, then the parent
                let killChildren = Process()
                killChildren.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
                killChildren.arguments = ["-9", "-P", String(pid)]
                try? killChildren.run()
                killChildren.waitUntilExit()

                // Now kill the expect process itself
                kill(pid, SIGKILL)
            }
        }
        process = nil
        outputPipe = nil
    }
}

/// Stub delegate for SwiftTerm Terminal - we only need to render, not handle events
private class TerminalRenderer: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}

/// Renders ANSI escape sequences using SwiftTerm's terminal emulator
/// SwiftTerm is a VT100/Xterm terminal emulator by Miguel de Icaza (MIT License)
/// https://github.com/migueldeicaza/SwiftTerm
func renderAnsiOutput(_ input: String) -> String {
    let cols = 120
    let rows = 100
    let delegate = TerminalRenderer()

    // Create a SwiftTerm terminal instance
    let terminal = Terminal(delegate: delegate, options: TerminalOptions(cols: cols, rows: rows))

    // Feed the raw ANSI data to the terminal
    if let data = input.data(using: .utf8) {
        let bytes = [UInt8](data)
        terminal.feed(byteArray: bytes)
    }

    // Extract rendered text from the terminal buffer
    var lines: [String] = []

    for row in 0..<rows {
        // getCharData accesses the visible buffer
        var lineText = ""
        for col in 0..<cols {
            if let charData = terminal.getCharData(col: col, row: row) {
                let str = String(charData.getCharacter())
                lineText += str.isEmpty ? " " : str
            } else {
                lineText += " "
            }
        }
        // Trim trailing spaces
        lineText = String(lineText.reversed().drop(while: { $0 == " " }).reversed())
        lines.append(lineText)
    }

    // Remove trailing empty lines
    while let last = lines.last, last.isEmpty {
        lines.removeLast()
    }

    return lines.joined(separator: "\n")
}

func parseUsageOutput(_ output: String) -> UsageInfo? {
    guard !output.isEmpty else { return nil }

    // Render ANSI sequences into a proper text buffer
    let cleanOutput = renderAnsiOutput(output)

    var sessionPercent: String?
    var weeklyPercent: String?
    var sessionResets: String?
    var weeklyResets: String?

    // Find "Current session" section
    if let lastSessionRange = cleanOutput.range(of: "Current session", options: [.backwards, .caseInsensitive]) {
        let afterSession = cleanOutput[lastSessionRange.upperBound...]
        // Find next section or end
        let endRange = afterSession.range(of: "Current week") ?? afterSession.endIndex..<afterSession.endIndex
        let sessionSection = afterSession[..<endRange.lowerBound]
        if let match = sessionSection.range(of: #"\d+%"#, options: .regularExpression) {
            sessionPercent = String(sessionSection[match])
        }
        // Extract reset time - look for time pattern like "3pm" or "3:00pm"
        if let resetMatch = sessionSection.range(of: #"\d{1,2}(:\d{2})?[ap]m"#, options: [.regularExpression, .caseInsensitive]) {
            sessionResets = String(sessionSection[resetMatch])
        }
    }

    // Look specifically for "Current week (all models)" to get the combined usage across all models
    if let allModelsRange = cleanOutput.range(of: "Current week (all models)", options: .backwards) {
        let afterAllModels = cleanOutput[allModelsRange.upperBound...]
        if let match = afterAllModels.range(of: #"\d+%"#, options: .regularExpression) {
            weeklyPercent = String(afterAllModels[match])
        }
        // Extract weekly reset date (e.g., "Resets Feb 2 at 1:59pm")
        if let resetMatch = afterAllModels.range(of: #"Resets [^(\n]+"#, options: .regularExpression) {
            let resetStr = String(afterAllModels[resetMatch])
            // Extract after "Resets "
            weeklyResets = String(resetStr.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }
    }

    guard sessionPercent != nil || weeklyPercent != nil else { return nil }

    return UsageInfo(
        sessionPercent: sessionPercent,
        weeklyPercent: weeklyPercent,
        sessionResets: sessionResets,
        weeklyResets: weeklyResets
    )
}
