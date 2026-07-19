import AppKit
import Darwin

/// A user-facing application, the PID to signal, and an approximate resource snapshot.
struct NamedProcess {
    let name: String
    let pid: pid_t
    /// Recent CPU usage as a percentage (may exceed 100 across multiple cores).
    let cpuPercent: Double
    /// Resident memory in megabytes.
    let memoryMB: Double
}

/// Which signal to send when terminating a process.
enum KillSignal {
    case term  // SIGTERM — graceful; the app can clean up / prompt to save.
    case kill  // SIGKILL — immediate and unconditional.

    var rawValue: Int32 { self == .kill ? SIGKILL : SIGTERM }
    var name: String { self == .kill ? "SIGKILL" : "SIGTERM" }
}

/// Lists user-facing applications and terminates them.
enum ProcessManager {

    /// Regular foreground applications — the ones in the ⌘-Tab switcher — sorted
    /// case-insensitively by name.
    ///
    /// Using `NSWorkspace` (rather than enumerating every PID) means helper/child
    /// processes never appear; only their parent app does. Restricting to `.regular`
    /// activation policy further drops menu-bar agents, XPC helpers, and system
    /// daemons, leaving a short list of recognizable parent apps. This app is
    /// itself excluded.
    static func userApplications() -> [NamedProcess] {
        let selfPID = getpid()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.processIdentifier > 0 && $0.processIdentifier != selfPID }
            .compactMap { app -> (name: String, pid: pid_t)? in
                guard let name = app.localizedName ?? app.bundleIdentifier else { return nil }
                return (name, app.processIdentifier)
            }

        let stats = resourceStats(for: apps.map(\.pid))

        return apps
            .map { app in
                let stat = stats[app.pid]
                return NamedProcess(
                    name: app.name,
                    pid: app.pid,
                    cpuPercent: stat?.cpu ?? 0,
                    memoryMB: stat?.memoryMB ?? 0
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Send the given signal to the process.
    static func kill(_ process: NamedProcess, signal: KillSignal) {
        Darwin.kill(process.pid, signal.rawValue)
    }

    /// Approximate CPU% and resident memory for the given PIDs, via a single `ps` call.
    /// Covers only the main process of each app, not its helper children.
    private static func resourceStats(for pids: [pid_t]) -> [pid_t: (cpu: Double, memoryMB: Double)] {
        guard !pids.isEmpty else { return [:] }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        // pid, %cpu, and rss (resident set size in KB); trailing `=` suppresses headers.
        task.arguments = ["-o", "pid=,%cpu=,rss=", "-p", pids.map(String.init).joined(separator: ",")]

        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
        } catch {
            NSLog("OpenSwitch: failed to read process stats: \(error)")
            return [:]
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [:] }

        var result: [pid_t: (cpu: Double, memoryMB: Double)] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 3,
                  let pid = pid_t(fields[0]),
                  let cpu = Double(fields[1]),
                  let rssKB = Double(fields[2]) else { continue }
            result[pid] = (cpu, rssKB / 1024)
        }
        return result
    }
}
