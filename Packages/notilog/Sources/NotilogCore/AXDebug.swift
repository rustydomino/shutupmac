import ApplicationServices

func dumpAXSubtree(
    _ element: AXUIElement,
    depth: Int = 0,
    maxDepth: Int = 5,
    visited: inout Set<String>,
    diagnosticHandler: DiagnosticHandler
) {
    if depth > maxDepth {
        return
    }

    let key = elementKey(element)

    if visited.contains(key) {
        return
    }

    visited.insert(key)
    
    let indent = String(repeating: "  ", count: depth)

    let role = strAttr(element, kAXRoleAttribute) ?? ""
    let subrole = strAttr(element, kAXSubroleAttribute) ?? ""
    let identifier = strAttr(element, kAXIdentifierAttribute) ?? ""
    let title = strAttr(element, kAXTitleAttribute) ?? ""
    let value = strAttr(element, kAXValueAttribute) ?? ""
    let description = strAttr(element, kAXDescriptionAttribute) ?? ""

    var parts: [String] = []

    if !role.isEmpty { parts.append("role=\"\(role)\"") }
    if !subrole.isEmpty { parts.append("subrole=\"\(subrole)\"") }
    if !identifier.isEmpty { parts.append("identifier=\"\(identifier)\"") }
    if !title.isEmpty { parts.append("title=\"\(title)\"") }
    if !value.isEmpty { parts.append("value=\"\(value)\"") }
    if !description.isEmpty { parts.append("description=\"\(description)\"") }

    diagnosticHandler(
        "\(indent)\(parts.joined(separator: " "))"
    )

    for childAttribute in [
        kAXChildrenAttribute,
        kAXVisibleChildrenAttribute,
        "AXChildrenInNavigationOrder"
    ] {
        for child in children(element, childAttribute) {
            dumpAXSubtree(
                child, 
                depth: depth + 1, 
                maxDepth: maxDepth,
                visited: &visited,
                diagnosticHandler: diagnosticHandler
            )
        }
    }
}
