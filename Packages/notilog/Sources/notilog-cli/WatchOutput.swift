import Foundation

struct WatchOutput {
    let isQuiet: Bool

    func routine(_ message: String) {
        guard !isQuiet else {
            return
        }

        print(message)
    }

    func routineError(_ message: String) {
        guard !isQuiet else {
            return
        }

        fputs(message, stderr)
    }
}
