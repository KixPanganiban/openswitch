import AppKit
import Darwin

/// A user-facing application and the PID to signal.
struct NamedProcess {
    let name: String
    let pid: pid_t
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
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.processIdentifier > 0 && $0.processIdentifier != selfPID }
            .compactMap { app -> NamedProcess? in
                guard let name = app.localizedName ?? app.bundleIdentifier else { return nil }
                return NamedProcess(name: name, pid: app.processIdentifier)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Send the given signal to the process.
    static func kill(_ process: NamedProcess, signal: KillSignal) {
        Darwin.kill(process.pid, signal.rawValue)
    }
}
