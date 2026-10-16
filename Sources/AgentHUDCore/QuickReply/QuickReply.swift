import AgentHUDSupport
import Foundation

/// Sends the user's next message into a session from the HUD, so a reply can be answered where it was read.
///
/// - Codex: the Desktop app that owns the thread starts the turn itself (`thread-follower-start-turn` over its local
///   IPC), so it runs with the thread's own model, permissions and folder and shows in Codex as it happens. A thread
///   no Desktop window owns is resumed by the bundled CLI instead.
/// - Claude Code: the installed engine resumes the session headless (`claude -p --resume`). The turn is written to the
///   same transcript, so its reply reaches the HUD the usual way, but the Claude window does not show it live; tool
///   approvals still come to the HUD through the permission hook.
///
/// The reply itself is not awaited here: it arrives as the session's next completion.
public enum QuickReply {
    public enum Failure: Error, Equatable, Sendable {
        case emptyMessage
        case unsupported(String)
        case sessionNotFound
        case engineNotFound
        case rejected(String)

        public var message: String {
            switch self {
            case .emptyMessage: return L10n.text("消息是空的", "The message is empty")
            case .unsupported(let vendor): return L10n.text("\(vendor) 暂不支持快捷回复", "\(vendor) has no quick reply")
            case .sessionNotFound: return L10n.text("找不到这个会话", "Session not found")
            case .engineNotFound: return L10n.text("找不到客户端程序", "Client not found")
            case .rejected(let reason): return L10n.text("发送失败：\(reason)", "Not sent: \(reason)")
            }
        }
    }

    /// How a message was taken: by Codex Desktop live, or by a background run.
    public enum Delivery: Equatable, Sendable {
        case live
        case background
    }

    static let hostOnlyPrefixes = ["CLAUDE", "ANTHROPIC_", "MCP_", "CODEX_INTERNAL", "XPC_", "__CF"]
    static let hostOnlyNames: Set<String> = ["CLAUDECODE", "OLDPWD", "PWD", "API_TIMEOUT_MS", "DISABLE_MICROCOMPACT", "GIT_EDITOR"]

    public static func supports(vendor: String) -> Bool { vendor == "Claude" || vendor == "Codex" }

    public static func send(_ text: String, to completion: SessionCompletion,
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) async throws -> Delivery {
        try await send(text, vendor: completion.vendor, sessionID: completion.sessionID, home: home)
    }

    /// - vendor: "Claude" or "Codex", the session's own client.
    public static func send(_ text: String, vendor: String, sessionID: String,
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) async throws -> Delivery {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw Failure.emptyMessage }
        switch vendor {
        case "Codex":
            return try await CodexQuickReply.send(message, threadID: sessionID, home: home)
        case "Claude":
            try ClaudeQuickReply.send(message, sessionID: sessionID, home: home)
            return .background
        default:
            throw Failure.unsupported(vendor)
        }
    }

    /// Where a session's log is on this Mac: a Claude Code transcript or a Codex rollout.
    public static func transcriptPath(vendor: String, sessionID: String,
                                      home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        switch vendor {
        case "Claude": return ClaudeQuickReply.transcript(sessionID: sessionID, home: home)?.path
        case "Codex": return CodexQuickReply.rollout(threadID: sessionID, home: home)?.path
        default: return nil
        }
    }

    /// How a session's latest turn is going, read from the end of its log.
    public struct Progress: Equatable, Sendable {
        /// The turn after the latest prompt is still going.
        public var running: Bool
        /// What it is doing right now, such as a tool and what it is for; nil while it only writes or thinks.
        public var activity: String?
        /// The latest text it has written in this turn.
        public var text: String?
        public init(running: Bool = false, activity: String? = nil, text: String? = nil) {
            self.running = running; self.activity = activity; self.text = text
        }
    }

    public static func progress(vendor: String, transcriptPath: String) -> Progress {
        guard let handle = FileHandle(forReadingAtPath: transcriptPath) else { return Progress() }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 2 * 1024 * 1024
        try? handle.seek(toOffset: size > window ? size - window : 0)
        let lines = ((try? handle.readToEnd()) ?? Data()).split(separator: 0x0A)
        var progress = Progress()
        // Walk back to the latest prompt, keeping the newest text, the newest activity and whether the turn ended.
        var ended: Bool?
        for line in lines.reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            switch vendor {
            case "Claude":
                guard object["isSidechain"] as? Bool != true, let type = object["type"] as? String,
                      let message = object["message"] as? [String: Any] else { continue }
                if type == "user" {
                    if let content = message["content"] as? String, !content.isEmpty { progress.running = ended != true; return progress }
                    if let blocks = message["content"] as? [[String: Any]], blocks.contains(where: { $0["type"] as? String == "text" }) {
                        progress.running = ended != true; return progress
                    }
                    continue
                }
                guard type == "assistant", let blocks = message["content"] as? [[String: Any]] else { continue }
                if ended == nil { ended = (message["stop_reason"] as? String) == "end_turn" }
                for block in blocks.reversed() {
                    if progress.text == nil, block["type"] as? String == "text", let text = block["text"] as? String,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        progress.text = SessionCompletion.wholeReply(text)
                    }
                    if progress.activity == nil, ended != true, block["type"] as? String == "tool_use", let name = block["name"] as? String {
                        let input = block["input"] as? [String: Any]
                        let what = (input?["description"] as? String) ?? (input?["file_path"] as? String) ?? (input?["pattern"] as? String)
                        progress.activity = what.map { "\(name) — \($0)" } ?? name
                    }
                }
            case "Codex":
                guard let payload = object["payload"] as? [String: Any], let kind = payload["type"] as? String else { continue }
                switch (object["type"] as? String, kind) {
                case ("event_msg", "user_message"):
                    progress.running = ended != true; return progress
                case ("event_msg", "task_complete"), ("event_msg", "turn_aborted"):
                    if ended == nil { ended = true }
                case ("event_msg", "agent_message"):
                    if ended == nil { ended = false }
                    if progress.text == nil { progress.text = SessionCompletion.wholeReply(payload["message"] as? String) }
                case ("response_item", "function_call"), ("response_item", "custom_tool_call"), ("response_item", "local_shell_call"):
                    if ended == nil { ended = false }
                    if progress.activity == nil, ended != true { progress.activity = payload["name"] as? String ?? kind }
                default:
                    if ended == nil, object["type"] as? String == "event_msg", kind == "task_started" { ended = false }
                }
            default:
                return progress
            }
        }
        progress.running = ended == false
        return progress
    }

    /// The session's last visible answer, read from the end of its log: the newest assistant text in a Claude Code
    /// transcript, the newest agent message in a Codex rollout.
    public static func lastReply(vendor: String, transcriptPath: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: transcriptPath) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 2 * 1024 * 1024
        try? handle.seek(toOffset: size > window ? size - window : 0)
        let tail = (try? handle.readToEnd()) ?? Data()
        for line in tail.split(separator: 0x0A).reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
            let text: String?
            switch vendor {
            case "Claude":
                guard object["type"] as? String == "assistant", object["isSidechain"] as? Bool != true,
                      let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] else { continue }
                text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
                    .joined(separator: "\n\n")
            case "Codex":
                guard object["type"] as? String == "event_msg", let payload = object["payload"] as? [String: Any] else { continue }
                switch payload["type"] as? String {
                case "agent_message": text = payload["message"] as? String
                case "task_complete": text = payload["last_agent_message"] as? String
                default: continue
                }
            default:
                return nil
            }
            if let reply = SessionCompletion.wholeReply(text) { return reply }
        }
        return nil
    }

    /// A GUI app starts with a minimal environment; a client run on its behalf needs a usable PATH and HOME. Variables a
    /// host app hands its own embedded clients are dropped: a Claude engine that finds the Claude app's would wait on that
    /// app's private channel for ever instead of using its own sign-in.
    static func environment(home: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment.filter { key, _ in
            !hostOnlyPrefixes.contains { key.hasPrefix($0) } && !hostOnlyNames.contains(key)
        }
        let path = ["\(home.path)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        environment["PATH"] = (path + (environment["PATH"].map { [$0] } ?? [])).joined(separator: ":")
        environment["HOME"] = home.path
        return environment
    }
}

enum ClaudeQuickReply {
    /// Background runs still going, kept so they are not released while they write the turn.
    nonisolated(unsafe) private static var running: [ChildProcess] = []
    private static let lock = NSLock()

    static func send(_ message: String, sessionID: String, home: URL) throws {
        guard sessionID.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil,
              let transcript = transcript(sessionID: sessionID, home: home) else { throw QuickReply.Failure.sessionNotFound }
        guard let engine = ClaudeEngineLocator.find(home: home) else { throw QuickReply.Failure.engineNotFound }
        let directory = workingDirectory(of: transcript) ?? home
        let child: ChildProcess
        do {
            child = try ChildProcess(engine, ["-p", "--resume", sessionID, "--output-format", "json"],
                                     environment: QuickReply.environment(home: home), directory: directory,
                                     input: true, stdoutLimit: 4 * 1024 * 1024)
            try child.write(Data(message.utf8))
        } catch {
            throw QuickReply.Failure.rejected(error.localizedDescription)
        }
        child.closeInput()
        lock.withLock { running.append(child) }
        Task.detached {
            // A turn with tools and approvals can take a long time; a day is only the ceiling.
            try? await child.waitForExit(before: Date().addingTimeInterval(86_400))
            lock.withLock { running.removeAll { $0 === child } }
        }
    }

    /// The session's log under `~/.claude/projects/<folder>/<id>.jsonl`.
    static func transcript(sessionID: String, home: URL) -> URL? {
        let projects = ClaudeSubscription.directory(home: home).appendingPathComponent("projects", isDirectory: true)
        guard let folders = try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else {
            return nil
        }
        return folders.lazy.map { $0.appendingPathComponent("\(sessionID).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The folder the session runs in, as its log records it.
    static func workingDirectory(of transcript: URL) -> URL? {
        guard let handle = try? FileHandle(forReadingFrom: transcript) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 256 * 1024)) ?? Data()
        for line in head.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let cwd = object["cwd"] as? String, !cwd.isEmpty else { continue }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: cwd, isDirectory: true)
            }
        }
        return nil
    }
}

enum CodexQuickReply {
    static let startTurnMethod = "thread-follower-start-turn"
    nonisolated(unsafe) private static var running: [ChildProcess] = []
    private static let lock = NSLock()

    static func send(_ message: String, threadID: String, home: URL) async throws -> QuickReply.Delivery {
        guard threadID.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil else {
            throw QuickReply.Failure.sessionNotFound
        }
        let socket = CodexLocator.dataDirectory(home: home).appendingPathComponent("ipc/ipc.sock").path
        let live: Bool = try await Task.detached {
            try startTurn(message, threadID: threadID, socket: socket)
        }.value
        if live { return .live }
        try resume(message, threadID: threadID, home: home)
        return .background
    }

    /// True once the owner has started the turn; false when no Desktop window owns the thread.
    static func startTurn(_ message: String, threadID: String, socket: String) throws -> Bool {
        let connection: CodexDesktopIPC
        do { connection = try CodexDesktopIPC(path: socket, timeout: 5) } catch { return false }
        defer { connection.close() }
        let initialized = try connection.request(method: "initialize", version: 0,
            source: "initializing-client", params: ["clientType": "agent-hud"])
        guard let clientID = (initialized["result"] as? [String: Any])?["clientId"] as? String, !clientID.isEmpty else {
            throw QuickReply.Failure.rejected("Codex IPC")
        }
        let owner: String
        do {
            let discovered = try connection.request(method: "thread-owner-discovery", version: 1,
                source: clientID, params: ["hostId": "local", "conversationId": threadID])
            guard let found = discovered["handledByClientId"] as? String, !found.isEmpty else { return false }
            owner = found
        } catch CodexDesktopIPC.Failure.rejected(let reason) where reason.hasPrefix("no-client-found") {
            return false
        } catch CodexDesktopIPC.Failure.timedOut {
            // No window answered for the thread in time: none of them has it open.
            return false
        }
        let params: [String: Any] = [
            "conversationId": threadID,
            // The owner fills in the thread's own model, permissions and folder from its latest settings.
            "turnStart": ["request": ["input": [["type": "text", "text": message, "text_elements": []]],
                                      "clientUserMessageId": UUID().uuidString.lowercased()],
                          "context": ["inheritThreadSettings": true]],
        ]
        do {
            _ = try connection.request(method: startTurnMethod, version: 2, source: clientID, target: owner, params: params)
        } catch CodexDesktopIPC.Failure.rejected(let reason) {
            throw QuickReply.Failure.rejected(reason)
        }
        return true
    }

    /// The thread's rollout, `sessions/<yyyy>/<mm>/<dd>/rollout-<time>-<id>.jsonl` in the data directory.
    static func rollout(threadID: String, home: URL) -> URL? {
        let sessions = CodexLocator.dataDirectory(home: home).appendingPathComponent("sessions", isDirectory: true)
        guard let files = FileManager.default.enumerator(at: sessions, includingPropertiesForKeys: nil) else { return nil }
        let suffix = "-\(threadID).jsonl"
        for case let file as URL in files where file.lastPathComponent.hasSuffix(suffix) { return file }
        return nil
    }

    /// The folder the thread runs in, from the `session_meta` that opens its rollout,
    /// `sessions/<yyyy>/<mm>/<dd>/rollout-<time>-<id>.jsonl` in the data directory.
    static func workingDirectory(threadID: String, home: URL) -> URL? {
        let sessions = CodexLocator.dataDirectory(home: home).appendingPathComponent("sessions", isDirectory: true)
        guard let files = FileManager.default.enumerator(at: sessions, includingPropertiesForKeys: nil) else { return nil }
        let suffix = "-\(threadID).jsonl"
        for case let file as URL in files where file.lastPathComponent.hasSuffix(suffix) {
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            let head = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
            guard let line = head.split(separator: 0x0A).first,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let cwd = (object["payload"] as? [String: Any])?["cwd"] as? String else { continue }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: cwd, isDirectory: true)
            }
        }
        return nil
    }

    /// No Desktop window owns the thread: the bundled CLI resumes it in the background.
    static func resume(_ message: String, threadID: String, home: URL) throws {
        guard let codex = CodexLocator.find(home: home) else { throw QuickReply.Failure.engineNotFound }
        let child: ChildProcess
        do {
            child = try ChildProcess(codex, ["exec", "--skip-git-repo-check", "resume", threadID, "-"],
                                     environment: QuickReply.environment(home: home),
                                     directory: workingDirectory(threadID: threadID, home: home) ?? home,
                                     input: true, stdoutLimit: 4 * 1024 * 1024)
            try child.write(Data(message.utf8))
        } catch {
            throw QuickReply.Failure.rejected(error.localizedDescription)
        }
        child.closeInput()
        lock.withLock { running.append(child) }
        Task.detached {
            try? await child.waitForExit(before: Date().addingTimeInterval(86_400))
            lock.withLock { running.removeAll { $0 === child } }
        }
    }
}
