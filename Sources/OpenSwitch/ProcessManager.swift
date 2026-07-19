import Darwin
import Foundation

/// A running process grouped by display name. One entry per unique name; `pids`
/// holds every process that shares that name so a kill can target all of them.
struct NamedProcess {
    let name: String
    let pids: [pid_t]
}

/// Lists and terminates processes owned by the current user.
enum ProcessManager {

    /// Unique named processes owned by the current user, sorted case-insensitively.
    ///
    /// Only the current user's processes are listed — those are the ones we can
    /// actually signal without elevated privileges. Processes are grouped by name,
    /// and this app itself is excluded so it can't be killed from its own menu.
    static func userProcesses() -> [NamedProcess] {
        guard let output = runPS() else { return [] }

        let selfPID = getpid()
        var pidsByName: [String: [pid_t]] = [:]

        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(of: " "),
                  let pid = pid_t(line[..<space]) else { continue }
            if pid == selfPID { continue }

            let commPath = line[line.index(after: space)...].trimmingCharacters(in: .whitespaces)
            let name = (commPath as NSString).lastPathComponent
            guard !name.isEmpty else { continue }

            pidsByName[name, default: []].append(pid)
        }

        return pidsByName
            .map { NamedProcess(name: $0.key, pids: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Send SIGTERM to every PID grouped under this name.
    static func kill(_ process: NamedProcess) {
        for pid in process.pids {
            Darwin.kill(pid, SIGTERM)
        }
    }

    /// Runs `ps` and returns its raw output (one `pid comm` pair per line).
    private static func runPS() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        // `pid=,comm=` — the trailing `=` suppresses the column headers.
        task.arguments = ["-o", "pid=,comm=", "-U", "\(getuid())"]

        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
        } catch {
            NSLog("OpenSwitch: failed to list processes: \(error)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
