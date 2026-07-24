/// Receives diagnostic messages produced by NotilogCore.
///
/// The host decides whether to discard, print, store, or display each message.
/// Messages supplied by NotilogCore do not include presentation prefixes such
/// as `[debug]`.
public typealias DiagnosticHandler = @Sendable (String) -> Void