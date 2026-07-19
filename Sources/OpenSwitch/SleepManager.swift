import Foundation

/// Puts the computer to sleep immediately.
enum SleepManager {
    /// Equivalent to running `pmset sleepnow`. Requires no elevated privileges.
    static func sleepNow() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["sleepnow"]
        do {
            try task.run()
        } catch {
            NSLog("OpenSwitch: failed to sleep: \(error)")
        }
    }
}
