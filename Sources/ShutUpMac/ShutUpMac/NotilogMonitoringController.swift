import Foundation
import NotilogCore

/// Schedules Notilog monitoring cycles on one private serial queue.
///
/// The runtime is created, used, and destroyed on this queue so that scans
/// cannot overlap and the database connection remains queue-confined.
nonisolated final class NotilogMonitoringController: @unchecked Sendable {
    private let queue = DispatchQueue(
        label: "com.shutupmac.notilog-monitoring"
    )

    private let interval: TimeInterval
    
    private let onActivityItems:
        @MainActor @Sendable ([ActivityItem]) -> Void
    
    private var timer: DispatchSourceTimer?
    private var runtime: NotilogMonitoringRuntime?
    private var isStarted = false

    init(
        interval: TimeInterval = 1.0,
        onActivityItems: @escaping
            @MainActor @Sendable ([ActivityItem]) -> Void
    ) {
        self.interval = interval
        self.onActivityItems = onActivityItems
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isStarted else {
                return
            }

            do {
                let runtime = try NotilogMonitoringRuntime()
                let timer = DispatchSource.makeTimerSource(
                    queue: self.queue
                )

                timer.schedule(
                    deadline: .now(),
                    repeating: self.interval,
                    leeway: .milliseconds(100)
                )

                timer.setEventHandler { [weak self] in
                    self?.processCycle()
                }

                self.runtime = runtime
                self.timer = timer
                self.isStarted = true

                timer.resume()
                print("Notilog monitoring started")
            } catch {
                print(
                    "Could not start Notilog monitoring: \(error)"
                )
            }
        }
    }

    func stop() {
        queue.sync {
            guard isStarted else {
                return
            }

            timer?.setEventHandler {}
            timer?.cancel()

            timer = nil
            runtime = nil
            isStarted = false

            print("Notilog monitoring stopped")
        }
    }

    private func processCycle() {
        guard let runtime else {
            return
        }

        do {
            let timestamp = Date()

            let result = try runtime.processOneCycle(
                at: timestamp
            )

            let activityItems = ActivityItemFactory.makeItems(
                from: result,
                verificationTimestamp: timestamp
            )

            guard !activityItems.isEmpty else {
                return
            }

            Task { @MainActor [onActivityItems, activityItems] in
                onActivityItems(activityItems)
            }

            print(
                "Notilog monitoring cycle produced "
                + "\(activityItems.count) activity item(s)"
            )
        } catch {
            print(
                "Notilog monitoring cycle failed: \(error)"
            )
        }
    }
}
