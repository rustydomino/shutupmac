import Darwin
import Foundation

public final class MonitoringProcessLock {
    private var fileDescriptor: Int32?

    public init(lockFileURL: URL) throws {
        let descriptor = lockFileURL.path.withCString { path in
            Darwin.open(
                path,
                O_CREAT | O_RDWR,
                S_IRUSR | S_IWUSR
            )
        }

        guard descriptor >= 0 else {
            throw MonitoringProcessLockError.openFailed(
                lockFileURL: lockFileURL,
                errorCode: errno
            )
        }

        guard flock(
            descriptor,
            LOCK_EX | LOCK_NB
        ) == 0 else {
            let errorCode = errno

            Darwin.close(descriptor)

            if errorCode == EWOULDBLOCK
                || errorCode == EAGAIN
            {
                throw MonitoringProcessLockError.alreadyRunning
            }

            throw MonitoringProcessLockError.lockFailed(
                lockFileURL: lockFileURL,
                errorCode: errorCode
            )
        }

        fileDescriptor = descriptor
    }

    deinit {
        release()
    }

    public func release() {
        guard let fileDescriptor else {
            return
        }

        self.fileDescriptor = nil

        flock(
            fileDescriptor,
            LOCK_UN
        )

        Darwin.close(fileDescriptor)
    }
}

public enum MonitoringProcessLockError:
    Error,
    LocalizedError,
    Equatable
{
    case alreadyRunning

    case openFailed(
        lockFileURL: URL,
        errorCode: Int32
    )

    case lockFailed(
        lockFileURL: URL,
        errorCode: Int32
    )

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Notilog monitoring is already running."

        case let .openFailed(lockFileURL, errorCode):
            return Self.systemErrorDescription(
                prefix: "Could not open the monitoring lock",
                lockFileURL: lockFileURL,
                errorCode: errorCode
            )

        case let .lockFailed(lockFileURL, errorCode):
            return Self.systemErrorDescription(
                prefix: "Could not acquire the monitoring lock",
                lockFileURL: lockFileURL,
                errorCode: errorCode
            )
        }
    }

    private static func systemErrorDescription(
        prefix: String,
        lockFileURL: URL,
        errorCode: Int32
    ) -> String {
        let systemMessage =
            String(cString: strerror(errorCode))

        return "\(prefix) at "
            + "\(lockFileURL.path): "
            + "\(systemMessage)"
    }
}