import SwiftUI
import AppKit
import Carbon

struct HotKeyRecorderView: View {
    let title: String
    @Binding var encodedHotKey: String
    let defaultHotKey: HotKey
    let otherEncodedHotKey: String
    let onChange: () -> Void
    let onRecordingStarted: () -> Void
    let onRecordingEnded: () -> Void

    @State private var isRecording = false
    @State private var errorMessage: String?

    private var currentHotKey: HotKey {
        HotKey.decode(encodedHotKey) ?? defaultHotKey
    }

    private var otherHotKey: HotKey? {
        HotKey.decode(otherEncodedHotKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .frame(width: 170, alignment: .leading)

                HotKeyRecorderButton(
                    displayString: currentHotKey.displayString,
                    isRecording: $isRecording,
                    onStartRecording: {
                        errorMessage = nil
                        onRecordingStarted()
                    },
                    onCaptured: recordShortcut,
                    onCancel: {
                        isRecording = false
                        onRecordingEnded()
                    }
                )
                .frame(width: 130, height: 28)

                Button("Reset") {
                    encodedHotKey = defaultHotKey.encodedString
                    errorMessage = nil
                    onChange()
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 170)
            }
        }
    }

    private func recordShortcut(from event: NSEvent) {
        defer {
            isRecording = false
            onRecordingEnded()
        }

        guard let candidate = HotKey.from(event: event) else {
            errorMessage = "Use a letter or number key."
            return
        }

        guard candidate.isValidGlobalShortcut else {
            errorMessage = "Use at least two of Control, Option, and Command."
            return
        }

        if candidate == currentHotKey {
            errorMessage = nil
            return
        }

        if let otherHotKey, candidate == otherHotKey {
            errorMessage = "This shortcut is already used by another ShutUpMac action."
            return
        }

        guard HotKeyAvailability.isAvailable(candidate) else {
            errorMessage = "That shortcut is unavailable or already in use."
            return
        }

        encodedHotKey = candidate.encodedString
        errorMessage = nil
        onChange()
    }
}

private struct HotKeyRecorderButton: NSViewRepresentable {
    let displayString: String
    @Binding var isRecording: Bool
    let onStartRecording: () -> Void
    let onCaptured: (NSEvent) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(title: "", target: context.coordinator, action: #selector(Coordinator.clicked))

        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)

        context.coordinator.button = button

        button.onCaptured = { event in
            context.coordinator.captured(event)
        }

        button.onCancelled = {
            context.coordinator.cancelled()
        }

        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        context.coordinator.parent = self

        button.title = isRecording ? "Press shortcut…" : displayString
        button.isRecording = isRecording
    }

    final class Coordinator: NSObject {
        var parent: HotKeyRecorderButton
        weak var button: RecorderButton?

        init(parent: HotKeyRecorderButton) {
            self.parent = parent
        }

        @objc func clicked() {
            parent.onStartRecording()
            parent.isRecording = true

            DispatchQueue.main.async {
                self.button?.window?.makeFirstResponder(self.button)
            }
        }

        func captured(_ event: NSEvent) {
            parent.onCaptured(event)
        }

        func cancelled() {
            parent.onCancel()
        }
    }
}

private final class RecorderButton: NSButton {
    var isRecording = false
    var onCaptured: ((NSEvent) -> Void)?
    var onCancelled: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            onCancelled?()
            return
        }

        onCaptured?(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else {
            return super.performKeyEquivalent(with: event)
        }

        keyDown(with: event)
        return true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            onCancelled?()
        }

        return true
    }
}
