#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Foundation

/// Dumps the accessibility geometry of a native macOS window. It is a local
/// developer tool: no screen recording, no network access and no stored values.
///
/// Usage:
///   swift scripts/ui_probe.swift --app Cornetta --window Summary
///   swift scripts/ui_probe.swift --pid 1234 --json /tmp/window.json
///
/// Frames are in screen points, with the origin at the top-left of the main display.

private struct Rect: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        x = Double(rect.origin.x)
        y = Double(rect.origin.y)
        width = Double(rect.width)
        height = Double(rect.height)
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var maxX: Double { x + width }
    var maxY: Double { y + height }
}

private struct Node: Codable {
    let role: String
    let subrole: String?
    let title: String?
    let description: String?
    let identifier: String?
    let frame: Rect?
    let path: [Int]
    let children: [Node]
}

private struct WindowReport: Codable {
    let generatedAt: String
    let appName: String
    let pid: pid_t
    let title: String
    let frame: Rect?
    let contentFrame: Rect?
    let titleBarFrame: Rect?
    let tree: Node?
    let warnings: [String]
}

private struct Options {
    var app: String?
    var pid: pid_t?
    var window: String?
    var jsonPath: String?
    var depth = 8
    var maxNodes = 3000
}

private struct CGWindowInfo {
    let title: String
    let frame: CGRect
}

private func cgWindows(for pid: pid_t, title: String?) -> [CGWindowInfo] {
    guard let raw = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] else { return [] }
    return raw.compactMap { entry in
        guard let owner = entry[kCGWindowOwnerPID as String] as? Int,
              owner == Int(pid),
              let layer = entry[kCGWindowLayer as String] as? Int,
              layer == 0,
              let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              frame.width > 0, frame.height > 0 else { return nil }
        let name = entry[kCGWindowName as String] as? String ?? ""
        if let title, !title.isEmpty,
           !name.localizedCaseInsensitiveContains(title) {
            return nil
        }
        return CGWindowInfo(title: name, frame: frame)
    }
}

private func parseOptions() -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while !arguments.isEmpty {
        let argument = arguments.removeFirst()
        switch argument {
        case "--app":
            options.app = arguments.first
            if !arguments.isEmpty { arguments.removeFirst() }
        case "--pid":
            options.pid = arguments.first.flatMap(pid_t.init)
            if !arguments.isEmpty { arguments.removeFirst() }
        case "--window":
            options.window = arguments.first
            if !arguments.isEmpty { arguments.removeFirst() }
        case "--json":
            options.jsonPath = arguments.first
            if !arguments.isEmpty { arguments.removeFirst() }
        case "--depth":
            options.depth = arguments.first.flatMap(Int.init) ?? options.depth
            if !arguments.isEmpty { arguments.removeFirst() }
        case "--max-nodes":
            options.maxNodes = arguments.first.flatMap(Int.init) ?? options.maxNodes
            if !arguments.isEmpty { arguments.removeFirst() }
        case "--help", "-h":
            print("""
            Usage: swift scripts/ui_probe.swift [--app NAME | --pid PID] [--window TITLE]
                                             [--json PATH] [--depth N] [--max-nodes N]
            """)
            exit(0)
        default:
            FileHandle.standardError.write(Data("Unknown option: \(argument)\n".utf8))
            exit(2)
        }
    }
    return options
}

private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    guard error == .success else { return nil }
    return value
}

private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
}

private func frame(of element: AXUIElement) -> CGRect? {
    guard let positionValue = attribute(element, kAXPositionAttribute),
          let sizeValue = attribute(element, kAXSizeAttribute),
          CFGetTypeID(positionValue) == AXValueGetTypeID(),
          CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    var size = CGSize.zero
    let position = unsafeBitCast(positionValue, to: AXValue.self)
    let dimensions = unsafeBitCast(sizeValue, to: AXValue.self)
    guard AXValueGetValue(position, .cgPoint, &point),
          AXValueGetValue(dimensions, .cgSize, &size) else { return nil }
    return CGRect(origin: point, size: size)
}

private func role(of element: AXUIElement) -> String {
    stringAttribute(element, kAXRoleAttribute) ?? "AXUnknown"
}

private func makeNode(_ element: AXUIElement, depth: Int, path: [Int],
                      options: Options, count: inout Int) -> Node? {
    guard count < options.maxNodes else { return nil }
    count += 1
    let currentRole = role(of: element)
    var children: [Node] = []
    if depth < options.depth, let rawChildren = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
        for (index, child) in rawChildren.enumerated() {
            if let node = makeNode(child, depth: depth + 1, path: path + [index],
                                   options: options, count: &count) {
                children.append(node)
            }
        }
    }
    return Node(role: currentRole,
                subrole: stringAttribute(element, kAXSubroleAttribute),
                title: stringAttribute(element, kAXTitleAttribute),
                description: stringAttribute(element, kAXDescriptionAttribute),
                identifier: stringAttribute(element, kAXIdentifierAttribute),
                frame: frame(of: element).map(Rect.init),
                path: path,
                children: children)
}

private func nodes(in tree: Node) -> [Node] {
    [tree] + tree.children.flatMap(nodes(in:))
}

private func findRole(_ role: String, in tree: Node) -> Node? {
    if tree.role == role { return tree }
    for child in tree.children {
        if let found = findRole(role, in: child) { return found }
    }
    return nil
}

private func output(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
}

private func fail(_ text: String) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(1)
}

private let options = parseOptions()
let runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy != .prohibited }
let selectedApp: NSRunningApplication?
if let pid = options.pid {
    selectedApp = runningApps.first(where: { $0.processIdentifier == pid })
} else if let name = options.app {
    selectedApp = runningApps.first {
        $0.localizedName?.localizedCaseInsensitiveContains(name) == true
            || $0.bundleIdentifier?.localizedCaseInsensitiveContains(name) == true
    }
} else {
    selectedApp = nil
}
guard let app = selectedApp else {
    fail("App not found. Pass --app Cornetta or --pid <pid>.")
}
guard let pid = Optional(app.processIdentifier) else { fail("Invalid pid") }

let axApp = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(axApp, 2.0)
guard let windows = attribute(axApp, kAXWindowsAttribute) as? [AXUIElement], !windows.isEmpty else {
    output("Accessibility view unavailable. Falling back to CGWindowList for outer bounds.")
    output("Grant Accessibility to the terminal or jcode to read inner controls.")
    let fallback = cgWindows(for: pid, title: options.window)
    guard !fallback.isEmpty else {
        fail("No windows for \(app.localizedName ?? "app") (\(pid)).")
    }
    for window in fallback {
        output("Window: \(window.title)")
        output("Window frame: \(format(Rect(window.frame)))")
        if let jsonPath = options.jsonPath {
            let report = WindowReport(generatedAt: ISO8601DateFormatter().string(from: Date()),
                                      appName: app.localizedName ?? "unknown",
                                      pid: pid,
                                      title: window.title,
                                      frame: Rect(window.frame),
                                      contentFrame: nil,
                                      titleBarFrame: nil,
                                      tree: nil,
                                      warnings: ["Accessibility view unavailable; CGWindowList only."])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: URL(fileURLWithPath: jsonPath))
            output("Wrote \(jsonPath)")
        }
    }
    exit(0)
}

var warnings: [String] = []
var selectedWindow: AXUIElement?
for window in windows {
    let title = stringAttribute(window, kAXTitleAttribute) ?? ""
    if options.window == nil || title.localizedCaseInsensitiveContains(options.window ?? "") {
        selectedWindow = window
        break
    }
}
guard let window = selectedWindow else {
    fail("Window not found: \(options.window ?? "<first>")")
}

var count = 0
private let rootNode = makeNode(window, depth: 0, path: [], options: options, count: &count)
if count >= options.maxNodes { warnings.append("Node limit reached: \(count)") }

private let windowFrame = frame(of: window)
private let titleBar = rootNode.flatMap { findRole("AXTitleBar", in: $0) }
private let toolbar = rootNode.flatMap { findRole("AXToolbar", in: $0) }
private let titleBarFrame = titleBar?.frame
private var contentFrame: Rect?
if let windowFrame {
    var top = windowFrame.minY + 28
    if let titleBarFrame { top = max(top, titleBarFrame.maxY) }
    if let toolbarFrame = toolbar?.frame { top = max(top, toolbarFrame.maxY) }
    contentFrame = Rect(CGRect(x: windowFrame.minX, y: top,
                               width: windowFrame.width,
                               height: max(0, windowFrame.maxY - top)))
}

private let report = WindowReport(
    generatedAt: ISO8601DateFormatter().string(from: Date()),
    appName: app.localizedName ?? "unknown",
    pid: pid,
    title: stringAttribute(window, kAXTitleAttribute) ?? "",
    frame: windowFrame.map(Rect.init),
    contentFrame: contentFrame,
    titleBarFrame: titleBarFrame,
    tree: rootNode,
    warnings: warnings
)

if let jsonPath = options.jsonPath {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(report)
    try data.write(to: URL(fileURLWithPath: jsonPath))
    output("Wrote \(jsonPath)")
}

guard let root = report.tree, let content = report.contentFrame else {
    fail("The window has no accessibility frame.")
}
output("App: \(report.appName) (\(report.pid))")
output("Window: \(report.title)")
output("Window frame: \(format(report.frame))")
output("Content frame: \(format(content))")
output("Title bar: \(format(report.titleBarFrame))")

private let allNodes = nodes(in: root)
private let contentRect = content.cgRect
private let visible = allNodes.filter { node in
    guard let nodeFrame = node.frame?.cgRect else { return false }
    let contentRoles = ["AXButton", "AXTextField", "AXTextArea", "AXStaticText",
                        "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXScrollArea"]
    return contentRoles.contains(node.role) && nodeFrame.intersects(contentRect)
}

if let scroll = visible.first(where: { $0.role == "AXScrollArea" }), let scrollFrame = scroll.frame {
    output("")
    output("Scroll area: \(format(scroll.frame))")
    output("  left gap: \(format(scrollFrame.x - content.x))")
    output("  right gap: \(format(content.maxX - scrollFrame.maxX))")
    output("  bottom gap: \(format(content.maxY - scrollFrame.maxY))")
    output("  width: \(format(scrollFrame.width)) of \(format(content.width))")
}
if let text = visible.first(where: { $0.role == "AXTextArea" }), let textFrame = text.frame {
    output("Text area: \(format(text.frame))")
    output("  height: \(format(textFrame.height)), available below: \(format(content.maxY - textFrame.maxY))")
}
private let buttons = visible.filter { node in
    node.role == "AXButton" && !(node.title ?? node.description ?? "").isEmpty
}
if !buttons.isEmpty {
    output("")
    for button in buttons {
        if let buttonFrame = button.frame {
            let label = button.title ?? button.description ?? "?"
            output("Button \(label): \(format(button.frame))"
                + " bottom gap \(format(content.maxY - buttonFrame.maxY))"
                + " right gap \(format(content.maxX - buttonFrame.maxX))")
        }
    }
}
let visibleMaxY = visible.compactMap { $0.frame?.maxY }.max() ?? content.y
let visibleMaxX = visible.compactMap { $0.frame?.maxX }.max() ?? content.x
output("Visible content bottom: \(format(visibleMaxY)), empty bottom: \(format(content.maxY - visibleMaxY))")
output("Visible content right: \(format(visibleMaxX)), empty right: \(format(content.maxX - visibleMaxX))")

private func format(_ value: Double) -> String {
    String(format: "%.1f", value)
}

private func format(_ rect: Rect?) -> String {
    guard let rect else { return "n/a" }
    return "x=\(format(rect.x)) y=\(format(rect.y)) w=\(format(rect.width)) h=\(format(rect.height))"
}
