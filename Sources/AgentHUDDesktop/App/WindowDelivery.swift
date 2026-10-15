import AppKit
import AgentHUDCore
import ApplicationServices

/// Sends a quick reply into the agent app's own conversation — the Claude app or Codex — so it is the same
/// conversation everywhere: the session is opened in the app, the text is pasted into its message field and sent with
/// Return, exactly as if typed there. A message sent while the session is working is queued by the app as usual.
///
/// Typing into another app needs Nexa Agent to be trusted for Accessibility. The clipboard is restored afterwards.
@MainActor
enum WindowDelivery {
    /// The app that shows a session, by where the session lives.
    static func bundleID(for target: SessionNavigationTarget) -> String? {
        switch target {
        case .claudeDesktopSession: return "com.anthropic.claudefordesktop"
        case .codexThread: return "com.openai.codex"
        default: return nil
        }
    }

    static func appName(for target: SessionNavigationTarget) -> String {
        if case .codexThread = target { return "Codex" }
        return "Claude"
    }

    enum Failure: Error, Equatable {
        case notTrusted(String)
        case notOpened(String)
        case noField(String)

        var message: String {
            switch self {
            case .notTrusted(let app):
                return L10n.text("需要在 系统设置 → 隐私与安全性 → 辅助功能 里允许 Nexa Agent，才能把消息送进 \(app) 窗口。",
                                 "Allow Nexa Agent in System Settings → Privacy & Security → Accessibility to send into the \(app) window.")
            case .notOpened(let app): return L10n.text("没能打开 \(app) 里的这个对话", "Couldn't open this conversation in \(app)")
            case .noField(let app): return L10n.text("没找到 \(app) 的输入框，请在 \(app) 里发送", "Couldn't find \(app)'s message field; send it in \(app)")
            }
        }
    }

    /// Whether this session lives in an agent app whose own window a reply can go into.
    static func handles(_ target: SessionNavigationTarget?) -> Bool {
        guard let target else { return false }
        return bundleID(for: target) != nil
    }

    static func send(_ text: String, to target: SessionNavigationTarget) async throws {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw QuickReply.Failure.emptyMessage }
        let app = appName(for: target)
        guard let bundle = bundleID(for: target) else { throw Failure.notOpened(app) }
        guard AXIsProcessTrusted() else {
            // The value of kAXTrustedCheckOptionPrompt, spelled out: the global is not concurrency-safe in Swift 6.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            throw Failure.notTrusted(app)
        }
        guard await SessionNavigator.open(target) else { throw Failure.notOpened(app) }
        guard let running = await frontmost(bundle) else { throw Failure.notOpened(app) }
        // The conversation's view settles after the app comes forward.
        try? await Task.sleep(for: .milliseconds(700))
        guard focusMessageField(of: running) else { throw Failure.noField(app) }
        try? await Task.sleep(for: .milliseconds(120))
        await paste(message)
        try? await Task.sleep(for: .milliseconds(150))
        press(36)  // Return sends.
    }

    /// The app once it is in front, waiting up to three seconds for the link to bring it there.
    private static func frontmost(_ bundleID: String) async -> NSRunningApplication? {
        for _ in 0..<30 {
            if let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == bundleID { return app }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    /// Puts the caret in the conversation's message field: the focused text area when there is one, otherwise the
    /// lowest editable text area in the front window, which is where the composer sits.
    private static func focusMessageField(of app: NSRunningApplication) -> Bool {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        if let focused = element(root, kAXFocusedUIElementAttribute), isTextArea(focused) { return true }
        guard let window = element(root, kAXFocusedWindowAttribute) ?? element(root, kAXMainWindowAttribute) else { return false }
        var fields: [(AXUIElement, CGFloat)] = []
        collect(window, depth: 0, into: &fields)
        guard let field = fields.max(by: { $0.1 < $1.1 })?.0 else { return false }
        return AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
    }

    private static func collect(_ node: AXUIElement, depth: Int, into fields: inout [(AXUIElement, CGFloat)]) {
        guard depth < 60 else { return }
        if isTextArea(node) {
            var value: AnyObject?
            var origin = CGPoint.zero
            if AXUIElementCopyAttributeValue(node, kAXPositionAttribute as CFString, &value) == .success, let value {
                AXValueGetValue(value as! AXValue, .cgPoint, &origin)
            }
            fields.append((node, origin.y))
        }
        guard let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for child in children { collect(child, depth: depth + 1, into: &fields) }
    }

    private static func isTextArea(_ node: AXUIElement) -> Bool {
        let role = attribute(node, kAXRoleAttribute) as? String
        guard role == kAXTextAreaRole as String || role == kAXTextFieldRole as String else { return false }
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(node, kAXValueAttribute as CFString, &settable)
        return settable.boolValue
    }

    private static func attribute(_ node: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(node, name as CFString, &value) == .success ? value : nil
    }

    private static func element(_ node: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(node, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// Pastes `text` with ⌘V and puts back what the clipboard held before.
    private static func paste(_ text: String) async {
        let board = NSPasteboard.general
        let saved = board.pasteboardItems?.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        board.clearContents()
        board.setString(text, forType: .string)
        press(9, flags: .maskCommand)  // V
        try? await Task.sleep(for: .milliseconds(300))
        board.clearContents()
        if !saved.isEmpty { board.writeObjects(saved) }
    }

    private static func press(_ key: CGKeyCode, flags: CGEventFlags = []) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }
}
