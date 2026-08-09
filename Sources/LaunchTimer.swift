import Darwin
import Foundation

/// Reports how long the app took to get from process start to a blinking
/// cursor. The spec's budget is 500ms, and a budget nobody measures is a wish.
///
/// Off unless `DEXEDIT_LOG_LAUNCH=1` is set, so it can measure a Release build —
/// the only build whose number means anything — without logging in normal use.
enum LaunchTimer {
    private static var reported = false

    /// Timestamps a milestone on the way to the cursor, to show where the
    /// launch budget actually goes.
    static func mark(_ label: String) {
        guard ProcessInfo.processInfo.environment["DEXEDIT_LOG_LAUNCH"] == "1",
              let start = processStart
        else { return }
        NSLog("dexEdit launch → %@: %.0fms", label, Date().timeIntervalSince(start) * 1000)
    }

    static func editorReady() {
        guard !reported,
              ProcessInfo.processInfo.environment["DEXEDIT_LOG_LAUNCH"] == "1",
              let start = processStart
        else { return }

        reported = true
        let milliseconds = Date().timeIntervalSince(start) * 1000
        NSLog("dexEdit launch → editor ready: %.0fms", milliseconds)
    }

    /// When this process was spawned, straight from the kernel — the only
    /// honest starting line, since anything in Swift already missed dyld.
    private static var processStart: Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]

        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }

        let started = info.kp_proc.p_starttime
        return Date(
            timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000
        )
    }
}
