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
    private var childPid: pid_t = 0
    private var masterFd: Int32 = -1
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

        // Create isolated temp directory for working directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-usage-bar")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Get directory containing claude for PATH
        let claudeDir = (claudePath as NSString).deletingLastPathComponent

        // Create a pseudo-terminal
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else {
            isRefreshing = false
            onError(.launchFailed(error: "Failed to create PTY master"))
            return
        }

        guard grantpt(master) == 0, unlockpt(master) == 0 else {
            close(master)
            isRefreshing = false
            onError(.launchFailed(error: "Failed to configure PTY"))
            return
        }

        guard let slavePathPtr = ptsname(master) else {
            close(master)
            isRefreshing = false
            onError(.launchFailed(error: "Failed to get PTY slave path"))
            return
        }

        let slavePathStr = String(cString: slavePathPtr)
        let slave = open(slavePathStr, O_RDWR)
        guard slave >= 0 else {
            close(master)
            isRefreshing = false
            onError(.launchFailed(error: "Failed to open PTY slave"))
            return
        }

        // Set terminal size on master
        var winSize = winsize(ws_row: 100, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, TIOCSWINSZ, &winSize)

        self.masterFd = master

        // Set up posix_spawn file actions to redirect stdin/stdout/stderr to PTY slave
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, slave, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slave, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, slave, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, master)
        if slave > STDERR_FILENO {
            posix_spawn_file_actions_addclose(&fileActions, slave)
        }

        // Set up spawn attributes
        var spawnAttr: posix_spawnattr_t?
        posix_spawnattr_init(&spawnAttr)

        // Set working directory via file actions (chdir)
        posix_spawn_file_actions_addchdir_np(&fileActions, tempDir.path)

        // Build environment - use dumb terminal and no color for simpler output
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let user = ProcessInfo.processInfo.environment["USER"] ?? ""
        let envVars: [String] = [
            "PATH=\(claudeDir):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "HOME=\(home)",
            "USER=\(user)",
            "TERM=dumb",
            "NO_COLOR=1"
        ]

        // Build arguments (argv[0] should be program name)
        let args: [String] = ["claude", "/usage"]

        // Spawn the process using proper C string handling
        var pid: pid_t = 0
        var spawnResult: Int32 = -1

        // Convert strings to C strings and call posix_spawn
        let cArgs = args.map { strdup($0) } + [nil]
        let cEnv = envVars.map { strdup($0) } + [nil]

        defer {
            cArgs.forEach { if let p = $0 { free(p) } }
            cEnv.forEach { if let p = $0 { free(p) } }
            posix_spawn_file_actions_destroy(&fileActions)
            posix_spawnattr_destroy(&spawnAttr)
        }

        spawnResult = cArgs.withUnsafeBufferPointer { argvBuf in
            cEnv.withUnsafeBufferPointer { envpBuf in
                posix_spawn(
                    &pid,
                    claudePath,
                    &fileActions,
                    &spawnAttr,
                    UnsafeMutablePointer(mutating: argvBuf.baseAddress!),
                    UnsafeMutablePointer(mutating: envpBuf.baseAddress!)
                )
            }
        }

        // Close slave in parent - child has its own copy
        close(slave)

        guard spawnResult == 0 else {
            close(master)
            masterFd = -1
            isRefreshing = false
            onError(.launchFailed(error: "posix_spawn failed with error \(spawnResult)"))
            return
        }

        self.childPid = pid

        var accumulatedData = Data()
        var hasCompleted = false
        var hasSentTrustResponse = false

        // Set master to non-blocking mode
        let flags = fcntl(master, F_GETFL)
        _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)

        // Create a dispatch source to read from the PTY master
        let readSource = DispatchSource.makeReadSource(fileDescriptor: master, queue: .global(qos: .userInitiated))

        readSource.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(master, &buffer, buffer.count)

            if bytesRead > 0 {
                accumulatedData.append(contentsOf: buffer[0..<bytesRead])
                let accumulatedOutput = String(data: accumulatedData, encoding: .utf8) ?? ""

                // Check for trust dialog and auto-respond
                if !hasSentTrustResponse {
                    let rendered = renderAnsiOutput(accumulatedOutput)
                    if rendered.lowercased().contains("trust") || rendered.lowercased().contains("proceed") {
                        hasSentTrustResponse = true
                        var newline: [UInt8] = [0x0D] // CR
                        _ = write(master, &newline, 1)
                    }
                }

                // Check if we have complete data
                if !hasCompleted, let usage = parseUsageOutput(accumulatedOutput),
                   usage.sessionPercent != nil && usage.weeklyPercent != nil {
                    hasCompleted = true
                    DispatchQueue.main.async {
                        readSource.cancel()
                        self?.timeoutTimer?.invalidate()
                        self?.timeoutTimer = nil
                        self?.handleRefreshComplete(output: accumulatedOutput)
                    }
                }
            } else if bytesRead == 0 || (bytesRead < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
                // EOF or error
                if !hasCompleted {
                    hasCompleted = true
                    let accumulatedOutput = String(data: accumulatedData, encoding: .utf8) ?? ""
                    DispatchQueue.main.async {
                        readSource.cancel()
                        self?.timeoutTimer?.invalidate()
                        self?.timeoutTimer = nil
                        self?.handleRefreshComplete(output: accumulatedOutput)
                    }
                }
            }
        }

        readSource.setCancelHandler {
            // Cleanup handled in terminateProcess
        }

        readSource.resume()

        // Monitor child process exit
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var status: Int32 = 0
            _ = waitpid(pid, &status, 0)

            DispatchQueue.main.async {
                guard !hasCompleted else { return }
                hasCompleted = true
                let accumulatedOutput = String(data: accumulatedData, encoding: .utf8) ?? ""
                readSource.cancel()
                self?.timeoutTimer?.invalidate()
                self?.timeoutTimer = nil
                self?.handleRefreshComplete(output: accumulatedOutput)
            }
        }

        // Set timeout
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            if !hasCompleted {
                hasCompleted = true
                readSource.cancel()
            }
            self?.handleTimeout()
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
        if childPid > 0 {
            // Kill child process and any descendants
            let killChildren = Process()
            killChildren.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            killChildren.arguments = ["-9", "-P", String(childPid)]
            try? killChildren.run()
            killChildren.waitUntilExit()

            // Kill the main process
            kill(childPid, SIGKILL)
            childPid = 0
        }

        if masterFd >= 0 {
            close(masterFd)
            masterFd = -1
        }
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
                let char = charData.getCharacter()
                // Filter out null characters and replace with space
                if char == "\0" || char.asciiValue == 0 {
                    lineText += " "
                } else {
                    let str = String(char)
                    lineText += str.isEmpty ? " " : str
                }
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
