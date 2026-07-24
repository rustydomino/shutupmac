import ApplicationServices

func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return err == .success ? value : nil
}

func strAttr(_ element: AXUIElement, _ name: String) -> String? {
    attr(element, name) as? String
}

func children(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
    attr(element, name) as? [AXUIElement] ?? []
}

func elementKey(_ element: AXUIElement) -> String {
    "\(Unmanaged.passUnretained(element).toOpaque())"
}
