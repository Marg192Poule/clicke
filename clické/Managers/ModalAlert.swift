import AppKit

// MARK: - Modal Alert

/// Runs `NSAlert`s app-modally without freezing Swift concurrency.
///
/// `runModal()` called from a `Task` (or any block on the main dispatch queue) keeps that block
/// running for as long as the alert is up. The main queue is serial, so every other main-actor
/// task waits behind it: captures, timers and toasts all stop. Alerts are therefore started from
/// the run loop itself (`RunLoop.main.perform`), outside of any main-queue block, and shown one
/// at a time.
enum ModalAlert {
    private struct Request {
        let alert: NSAlert
        let completion: (NSApplication.ModalResponse) -> Void
    }

    private static var pending: [Request] = []
    private static var isRunning = false

    /// Shows `alert` as soon as the run loop is free (after any alert already on screen), then calls
    /// `completion` with the button that was clicked.
    static func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void = { _ in }) {
        pending.append(Request(alert: alert, completion: completion))
        scheduleNext()
    }

    private static func scheduleNext() {
        RunLoop.main.perform {
            MainActor.assumeIsolated {
                runNext()
            }
        }
    }

    private static func runNext() {
        guard !isRunning, !pending.isEmpty else { return }
        let request = pending.removeFirst()

        isRunning = true
        // Clické may run without a Dock icon: bring the alert in front of the active app.
        NSApp.activate()
        let response = request.alert.runModal()
        isRunning = false

        request.completion(response)
        if !pending.isEmpty {
            scheduleNext()
        }
    }
}
