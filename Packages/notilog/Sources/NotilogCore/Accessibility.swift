import ApplicationServices

public enum Accessibility {
     public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

   public static func promptForAccess() -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString

        let options = [
            promptKey: true
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }
}    
