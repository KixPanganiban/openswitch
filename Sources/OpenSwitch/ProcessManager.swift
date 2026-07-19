import AppKit
import Darwin

/// A user-facing application, the PID to signal, and an approximate resource snapshot.
struct NamedProcess {
    let name: String
    let pid: pid_t
    /// The app's icon, for display in the menu.
    let icon: NSImage?
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
            .compactMap { app -> (name: String, pid: pid_t, icon: NSImage?)? in
                guard let name = app.localizedName ?? app.bundleIdentifier else { return nil }
                return (name, app.processIdentifier, app.icon)
            }

        let stats = resourceStats(for: apps.map(\.pid))

        return apps
            .map { app in
                let stat = stats[app.pid]
                return NamedProcess(
                    name: app.name,
                    pid: app.pid,
                    icon: app.icon,
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

    /// Approximate aggregated CPU% and resident memory for each app PID.
    ///
    /// Every process in the system is attributed to the app "responsible" for it
    /// (its main app for helper/XPC children, matching how Activity Monitor groups
    /// them), then CPU and memory are summed per app. If the responsibility lookup
    /// is unavailable, this degrades to each app's main process only.
    private static func resourceStats(for appPIDs: [pid_t]) -> [pid_t: (cpu: Double, memoryMB: Double)] {
        guard !appPIDs.isEmpty, let output = allProcessStats() else { return [:] }

        let appSet = Set(appPIDs)
        var grouped: [pid_t: (cpu: Double, rssKB: Double)] = [:]  // keyed by responsible app PID
        var own: [pid_t: (cpu: Double, rssKB: Double)] = [:]      // per-process fallback

        for line in output.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 3,
                  let pid = pid_t(fields[0]),
                  let cpu = Double(fields[1]),
                  let rssKB = Double(fields[2]) else { continue }

            own[pid] = (cpu, rssKB)
            let owner = responsiblePID(for: pid)
            if appSet.contains(owner) {
                var total = grouped[owner, default: (0, 0)]
                total.cpu += cpu
                total.rssKB += rssKB
                grouped[owner] = total
            }
        }

        var result: [pid_t: (cpu: Double, memoryMB: Double)] = [:]
        for pid in appPIDs {
            let agg = grouped[pid] ?? own[pid] ?? (cpu: 0, rssKB: 0)
            result[pid] = (agg.cpu, agg.rssKB / 1024)
        }
        return result
    }

    /// One snapshot of every process: `pid %cpu rss(KB)` per line.
    private static func allProcessStats() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,%cpu=,rss="]

        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
        } catch {
            NSLog("OpenSwitch: failed to read process stats: \(error)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// The PID that macOS considers "responsible" for the given process — the app
    /// that spawned an XPC/helper child. Falls back to the PID itself if the
    /// private lookup is unavailable.
    private static func responsiblePID(for pid: pid_t) -> pid_t {
        responsibleForPID?(pid) ?? pid
    }

    /// `responsibility_get_pid_responsible_for_pid`, resolved once from the loaded
    /// system libraries. Private API — nil (and graceful degradation) if it's gone.
    private static let responsibleForPID: ((pid_t) -> pid_t)? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(rtldDefault, "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        typealias Fn = @convention(c) (pid_t) -> pid_t
        let fn = unsafeBitCast(symbol, to: Fn.self)
        return { fn($0) }
    }()
}
