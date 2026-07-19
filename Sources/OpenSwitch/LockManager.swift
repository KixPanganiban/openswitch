import Foundation

/// Locks the screen immediately (shows the login/password prompt).
enum LockManager {
    private typealias LockScreenFn = @convention(c) () -> Int32
    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"

    /// Invokes `SACLockScreenImmediate` from the private `login` framework.
    /// This is a true lock (not display sleep or fast-user-switch) and needs no
    /// special permission.
    static func lock() {
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
            NSLog("OpenSwitch: failed to load login framework")
            return
        }
        defer { dlclose(handle) }

        guard let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            NSLog("OpenSwitch: SACLockScreenImmediate unavailable")
            return
        }

        let lockScreen = unsafeBitCast(symbol, to: LockScreenFn.self)
        _ = lockScreen()
    }
}
