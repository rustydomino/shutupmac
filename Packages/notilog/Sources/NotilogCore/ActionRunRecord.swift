import Foundation

public struct ActionRunRecord {
    public let id: Int64
    public let createdAt: Date
    public let sessionID: String
    public let ruleName: String
    public let actionSummary: String
    public let resolvedActionSummary: String
    public let status: ActionRunStatus
    public let verificationStatus: ActionVerificationStatus?
    public let message: String
    public let exitCode: Int32?
    public let stdout: String
    public let stderr: String
    public let eventType: NotificationEventType
    public let eventTimestamp: Date
    public let notification: VisibleNotification

    public init(
        id: Int64,
        createdAt: Date,
        sessionID: String,
        ruleName: String,
        actionSummary: String,
        resolvedActionSummary: String,
        status: ActionRunStatus,
        verificationStatus: ActionVerificationStatus?,
        message: String,
        exitCode: Int32?,
        stdout: String,
        stderr: String,
        eventType: NotificationEventType,
        eventTimestamp: Date,
        notification: VisibleNotification
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sessionID = sessionID
        self.ruleName = ruleName
        self.actionSummary = actionSummary
        self.resolvedActionSummary = resolvedActionSummary
        self.status = status
        self.verificationStatus = verificationStatus
        self.message = message
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.eventType = eventType
        self.eventTimestamp = eventTimestamp
        self.notification = notification
    }
}
