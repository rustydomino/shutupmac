import Foundation

public enum Debug {
    public nonisolated(unsafe) static var enabled = false
    
    public static func log(_ message: @autoclosure () -> String) {
        guard enabled else {
            return
        }

        fputs("[debug] \(message())\n", stderr)
    }
}
