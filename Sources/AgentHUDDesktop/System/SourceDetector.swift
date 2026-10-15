import Foundation
import AgentHUDCore

/// Cheap, prompt-free detection of local agent installs for the first-launch screen.
enum SourceDetector {
    static func resolve(_ sources: [SourceStatus], report: UsageReport?) -> [SourceStatus] {
        guard let report else { return sources }
        return sources.map { source in
            // Shared account quota does not establish that either execution client supplied sessions.
            if source.provider == "Grok", source.name == "Grok CLI" || source.name == "Grok Bot" {
                guard report.sessions.contains(where: {
                    SessionSource(vendor: SessionSource.vendor(impliedBy: $0.agentId), client: $0.client).agentVendor == source.name
                }) else { return source }
                return SourceStatus(id: source.id, name: source.name, detail: source.detail, state: .ready(plan: nil),
                                    provider: source.provider, supportsLiveStatus: source.supportsLiveStatus)
            }
            let vendor: String
            switch source.id {
            case "claude-code": vendor = "Claude"
            case "codex-cli": vendor = "Codex"
            case "deepseek": vendor = "DeepSeek"
            default:
                if let additional = AdditionalSource(rawValue: source.id) { vendor = additional.vendor }
                else if let additional = OpenAgentSource(rawValue: source.id) { vendor = additional.name }
                else { return source }
            }
            if vendor == "DeepSeek", report.discoveredAgents.contains(where: { $0.id == "deepseek" && $0.connected }) {
                return SourceStatus(id: source.id, name: source.name, detail: source.detail, state: .ready(plan: nil),
                                    provider: source.provider, supportsLiveStatus: source.supportsLiveStatus)
            }
            let hasQuota = report.discoveredAgents.contains { agent in
                (agent.vendor == vendor || vendor == "OpenCode" && agent.vendor == "OpenCode Go") && report.snapshots.contains { $0.agentId == agent.id }
            }
            let hasSessions = report.consumers.contains { $0.vendor == vendor }
            let plan = report.subscriptions[vendor]
            if let notice = report.quotaNotice(vendor: vendor) ?? report.sourceNotices[vendor]
                ?? (vendor == "OpenCode" ? report.sourceNotices["OpenCode Go"] : nil) {
                return SourceStatus(id: source.id, name: source.name, detail: notice,
                    state: hasQuota || hasSessions || plan != nil ? .ready(plan: plan) : .unavailable,
                    provider: source.provider, supportsLiveStatus: source.supportsLiveStatus)
            }
            guard hasQuota || hasSessions || plan != nil else { return source }
            return SourceStatus(id: source.id, name: source.name, detail: source.detail, state: .ready(plan: plan),
                                provider: source.provider, supportsLiveStatus: source.supportsLiveStatus)
        }
    }

    static func detect(fileManager: FileManager = .default) -> [SourceStatus] {
        let home = fileManager.homeDirectoryForCurrentUser
        let engine = ClaudeEngineLocator.find(home: home, fileManager: fileManager)
        let claudeReady = engine != nil || fileManager.fileExists(atPath: home.appendingPathComponent(".claude/projects").path)
        let codexReady = CodexLocator.find() != nil
        let claudeDetail: String
        if engine != nil {
            claudeDetail = L10n.text("额度、会话与用量统计", "Quota, sessions and usage")
        } else if claudeReady {
            claudeDetail = L10n.text("已发现会话，安装并登录后读取额度", "Sessions found; install and sign in to read quota")
        } else {
            claudeDetail = L10n.text("安装并登录后读取用量", "Reads usage once installed and signed in")
        }
        // Nexa Agent connects Claude Code and Codex only.
        return [
            SourceStatus(
                id: "claude-code", name: "Claude",
                detail: claudeDetail,
                state: claudeReady ? .installed : .notDetected
            ),
            SourceStatus(
                id: "codex-cli", name: "Codex",
                detail: codexReady
                    ? L10n.text("额度、会话与用量统计", "Quota, sessions and usage")
                    : L10n.text("安装并登录后读取用量", "Reads usage once installed and signed in"),
                state: codexReady ? .installed : .notDetected
            ),
        ]
    }
}
