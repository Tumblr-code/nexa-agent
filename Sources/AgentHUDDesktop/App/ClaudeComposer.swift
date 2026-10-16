import AppKit
import AgentHUDCore
import ApplicationServices
import os

/// Sends a quick reply into a Claude app conversation from the background, so it is the same conversation everywhere
/// and nothing jumps in front of the user: the session is selected in the app without activating it, the text is
/// written into the conversation's message field through Accessibility and sent with the app's own Send button — or,
/// while a turn runs and the app shows Stop instead, with Return posted to the app, which queues it as usual. A draft
/// the user left in the field is put back afterwards.
///
/// Writing into another app needs Nexa Agent to be trusted for Accessibility.
@MainActor
enum ClaudeComposer {
    static let bundleID = "com.anthropic.claudefordesktop"
    private static let log = Logger(subsystem: "app.nexa.agent", category: "claude-composer")

    enum Failure: Error, Equatable {
        case notTrusted, notRunning, noField, notSent

        var message: String {
            switch self {
            case .notTrusted:
                return L10n.text("需要在 系统设置 → 隐私与安全性 → 辅助功能 里允许 Nexa Agent，才能把消息发进 Claude。",
                                 "Allow Nexa Agent in System Settings → Privacy & Security → Accessibility to send into Claude.")
            case .notRunning: return L10n.text("Claude 没有在运行", "Claude isn't running")
            case .noField: return L10n.text("没找到 Claude 的输入框", "Couldn't find Claude's message field")
            case .notSent: return L10n.text("Claude 没有接收这条消息，请在 Claude 里发送", "Claude didn't take the message; send it in Claude")
            }
        }
    }

    /// Whether this session lives in the Claude app.
    static func handles(_ target: SessionNavigationTarget?) -> Bool {
        if case .claudeDesktopSession = target { return true }
        return false
    }

    static func send(_ text: String, to target: SessionNavigationTarget) async throws {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw QuickReply.Failure.emptyMessage }
        log.info("send: trusted=\(AXIsProcessTrusted(), privacy: .public)")
        guard AXIsProcessTrusted() else {
            // The value of kAXTrustedCheckOptionPrompt, spelled out: the global is not concurrency-safe in Swift 6.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            throw Failure.notTrusted
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            throw Failure.notRunning
        }
        let front = NSWorkspace.shared.frontmostApplication
        // Select the conversation without bringing the app forward.
        if let url = SessionNavigator.url(for: target) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            _ = try? await NSWorkspace.shared.open(url, configuration: configuration)
            try? await Task.sleep(for: .milliseconds(600))
        }
        defer { giveBack(front) }

        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let field = messageField(in: root) else {
            log.error("no message field")
            throw Failure.noField
        }
        let draft = (value(of: field) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, message as CFString) == .success else {
            throw Failure.noField
        }
        try? await Task.sleep(for: .milliseconds(150))
        if let send = button(in: root, named: ["发送", "Send", "Send message", "发送消息"]) {
            log.info("pressing Send")
            AXUIElementPerformAction(send, kAXPressAction as CFString)
        } else {
            // A turn is running: Return queues the message, as typing it would.
            log.info("posting Return to the app")
            AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            for down in [true, false] {
                CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: down)?.postToPid(app.processIdentifier)
            }
        }
        // The field empties once the app has taken the message.
        var taken = false
        for _ in 0..<15 {
            try? await Task.sleep(for: .milliseconds(100))
            let now = (value(of: field) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if now != message { taken = true; break }
        }
        if !draft.isEmpty {
            AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, draft as CFString)
        }
        guard taken else {
            log.error("message stayed in the field")
            if draft.isEmpty { AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, "" as CFString) }
            throw Failure.notSent
        }
        log.info("sent")
    }

    /// Puts back the app the user was in if selecting the conversation brought Claude forward anyway.
    private static func giveBack(_ front: NSRunningApplication?) {
        guard let front, front.bundleIdentifier != bundleID,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else { return }
        let element = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    private static func messageField(in root: AXUIElement) -> AXUIElement? {
        var found: AXUIElement?
        visit(root) { node in
            guard (attribute(node, kAXRoleAttribute) as? String) == kAXTextAreaRole as String else { return false }
            var settable: DarwinBoolean = false
            AXUIElementIsAttributeSettable(node, kAXValueAttribute as CFString, &settable)
            if settable.boolValue { found = node; return true }
            return false
        }
        return found
    }

    private static func button(in root: AXUIElement, named names: [String]) -> AXUIElement? {
        var found: AXUIElement?
        visit(root) { node in
            guard (attribute(node, kAXRoleAttribute) as? String) == kAXButtonRole as String else { return false }
            let label = (attribute(node, kAXDescriptionAttribute) as? String) ?? (attribute(node, kAXTitleAttribute) as? String) ?? ""
            guard names.contains(label), (attribute(node, kAXEnabledAttribute) as? Bool) != false else { return false }
            found = node
            return true
        }
        return found
    }

    /// Depth-first over the app's windows until `match` says stop.
    private static func visit(_ root: AXUIElement, _ match: (AXUIElement) -> Bool) {
        var stack = (attribute(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        var seen = 0
        while let node = stack.popLast(), seen < 20_000 {
            seen += 1
            if match(node) { return }
            if let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] { stack.append(contentsOf: children.reversed()) }
        }
    }

    private static func value(of node: AXUIElement) -> String? { attribute(node, kAXValueAttribute) as? String }

    private static func attribute(_ node: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
    }
}
