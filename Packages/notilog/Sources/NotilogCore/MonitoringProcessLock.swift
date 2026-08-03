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
            throw NotilogError.monitoringLockOpenFailed(
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
                throw NotilogError.monitorAlreadyRunning
            }

            throw NotilogError.monitoringLockFailed(
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


