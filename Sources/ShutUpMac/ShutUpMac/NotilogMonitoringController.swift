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

    private var timer: DispatchSourceTimer?
    private var runtime: NotilogMonitoringRuntime?
    private var isStarted = false

    init(interval: TimeInterval = 1.0) {
        self.interval = interval
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
            let result = try runtime.processOneCycle(
                at: Date()
            )

            let activityCount =
                result.completedActionVerifications.count
                + result.recoveredEvents.count
                + result.events.count

            guard activityCount > 0 else {
                return
            }

            print(
                "Notilog monitoring cycle produced "
                + "\(activityCount) activity item(s)"
            )
        } catch {
            print(
                "Notilog monitoring cycle failed: \(error)"
            )
        }
    }
}
