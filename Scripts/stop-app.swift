import AppKit
import Foundation

// Stop legacy bundled copies too: path matching misses other build/output directories.
// The new executable's --stop-running-instance additionally covers unbundled/direct launches.
let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.publishflow.app")
for app in applications where !app.isTerminated {
    guard app.terminate() else {
        fputs("Inkpost refused to quit (pid \(app.processIdentifier)); replacement cancelled.\n", stderr)
        exit(1)
    }
}
let deadline = ProcessInfo.processInfo.systemUptime + 10
while applications.contains(where: { !$0.isTerminated }) {
    guard ProcessInfo.processInfo.systemUptime < deadline else {
        fputs("Existing Inkpost did not quit; replacement cancelled.\n", stderr)
        exit(1)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
