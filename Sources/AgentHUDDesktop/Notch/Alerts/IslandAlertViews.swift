import SwiftUI
import AgentHUDCore

struct IslandAlertCompactView: View {
    let alert: IslandAlert
    let cameraWidth: CGFloat
    let height: CGFloat
    let onOpen: () -> Void
    var waitingRequests: [PermissionRequest] = []
    @Environment(\.stripScale) private var scale
    @Environment(\.compactWings) private var wings

    /// What a finished turn's reminder says beside its agent.
    static var replyStatus: String { L10n.text("有新回复", "New reply") }

    /// A length at the scale of the dock this reminder grows from.
    private func s(_ value: CGFloat) -> CGFloat { (value * scale).rounded() }

    var body: some View {
        switch alert {
        case .permission(let request):
            PermissionAlertCompactView(request: request, cameraWidth: cameraWidth, height: height,
                                       waiting: max(1, waitingRequests.count))
        case .quota(let event):
            QuotaAlertCompactView(alert: event, cameraWidth: cameraWidth, height: height, onOpen: onOpen)
        case .resetCredits(let event):
            ResetCreditAlertCompactView(grant: event, cameraWidth: cameraWidth, height: height, onOpen: onOpen)
        case .completion(let event):
            Button(action: onOpen) {
                HStack(spacing: 0) {
                    HStack(spacing: s(8)) {
                        BotMark(vendor: event.agentVendor, size: s(17), phase: .done)
                        Text(event.agentVendor).font(.ui(s(13), .semibold)).lineLimit(1)
                    }.frame(width: wings?.leading ?? s(IslandController.alertWingWidth), alignment: .leading)
                    Color.clear.frame(width: wings?.gap ?? cameraWidth)
                    HStack(spacing: s(7)) {
                        TurnEndedSymbol(size: s(16))
                        Text(Self.replyStatus)
                            .font(.ui(s(12), .medium)).foregroundStyle(Color(alert.accent))
                    }.frame(width: wings?.trailing ?? s(IslandController.alertWingWidth), alignment: .trailing)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, wings?.padding ?? s(IslandController.alertSidePadding)).frame(height: height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("island-alert-sessionCompleted")
            .accessibilityLabel("\(event.agentVendor) · \(L10n.text("有新回复", "New reply")) · \(event.task)")
            .accessibilityHint(L10n.text("展开会话与 Token 用量操作", "Show session and token usage actions"))
        }
    }
}

struct IslandAlertDetailView: View {
    let alert: IslandAlert
    let onOpen: () -> Void
    let onDecide: (PermissionDecision) -> Void
    var onDismiss: () -> Void = {}
    var onOpenSession: () -> Void = {}
    var onOpenUsage: () -> Void = {}
    var sessionNavigationFailed = false
    var waitingRequests: [PermissionRequest] = []
    var onSelectRequest: (String) -> Void = { _ in }
    var body: some View {
        switch alert {
        case .permission(let request):
            PermissionAlertDetailView(request: request, onDecide: onDecide,
                                      all: waitingRequests, onSelect: onSelectRequest)
        case .quota(let event): QuotaAlertDetailView(alert: event, onOpen: onOpen)
        case .resetCredits(let event): ResetCreditAlertDetailView(grant: event, onOpen: onOpen)
        case .completion(let event):
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    BotMark(vendor: event.agentVendor, size: 24, phase: .done)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.agentVendor).font(.ui(13, .semibold))
                        Text(event.model).font(.ui(11)).foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    TurnEndedSymbol()
                    Text(L10n.text("有新回复", "New reply"))
                        .font(.ui(12, .medium)).foregroundStyle(Color(alert.accent))
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.65))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("island-alert-dismissCompletion")
                    .accessibilityLabel(L10n.text("关闭回复提醒", "Dismiss reply"))
                    .help(L10n.text("关闭回复提醒", "Dismiss reply"))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.task).font(.ui(15, .medium)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let reply = event.reply ?? event.message {
                        ReplyText(text: reply)
                    }
                }
                if QuickReply.supports(vendor: event.vendor) {
                    QuickReplyBar(vendor: event.vendor, sessionID: event.sessionID, agentName: event.agentVendor)
                }
                HStack {
                    Text(event.completedAt.formatted(date: .omitted, time: .shortened))
                    Spacer()
                    if let start = event.startedAt {
                        Text(Countdown.compact(max(0, event.completedAt.timeIntervalSince(start))))
                    }
                }.font(.tabular(11)).foregroundStyle(.white.opacity(0.5))
                CompletionAlertActions(hasSession: event.navigationTarget != nil,
                                       navigationFailed: sessionNavigationFailed,
                                       onOpenSession: onOpenSession, onOpenUsage: onOpenUsage)
            }.foregroundStyle(.white)
        }
    }
}

/// Session events share one panel: the selected card is open and the other events remain selectable rows.
struct IslandEventPanelView: View {
    let alert: IslandAlert
    let onOpen: () -> Void
    let onDecide: (PermissionDecision) -> Void
    var onDismiss: () -> Void = {}
    var onOpenSession: () -> Void = {}
    var onOpenUsage: () -> Void = {}
    var sessionNavigationFailed = false
    var events: [IslandAlert] = []
    var waitingRequests: [PermissionRequest] = []
    var onSelectRequest: (String) -> Void = { _ in }

    private var requests: [PermissionRequest] {
        if !waitingRequests.isEmpty { return waitingRequests }
        var values = events.compactMap { event -> PermissionRequest? in
            guard case .permission(let request) = event else { return nil }
            return request
        }
        if case .permission(let request) = alert, !values.contains(where: { $0.id == request.id }) {
            values.insert(request, at: 0)
        }
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }

    /// The other conversations' latest replies: one row per session, none for the session of the open card.
    private var replies: [SessionCompletion] {
        var openSession: String?
        if case .completion(let open) = alert { openSession = open.sessionID }
        var latest: [String: SessionCompletion] = [:], order: [String] = []
        for event in events {
            guard case .completion(let reply) = event, reply.id != alert.id, reply.sessionID != openSession else { continue }
            if let kept = latest[reply.sessionID] {
                if reply.completedAt > kept.completedAt { latest[reply.sessionID] = reply }
            } else {
                latest[reply.sessionID] = reply; order.append(reply.sessionID)
            }
        }
        return order.compactMap { latest[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IslandAlertDetailView(alert: alert, onOpen: onOpen, onDecide: onDecide,
                                  onDismiss: onDismiss,
                                  onOpenSession: onOpenSession, onOpenUsage: onOpenUsage,
                                  sessionNavigationFailed: sessionNavigationFailed,
                                  waitingRequests: requests, onSelectRequest: onSelectRequest)
                .accessibilityIdentifier("island-event-selected-\(alert.id)")

            if case .completion = alert, !requests.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(L10n.text("待审批", "Waiting"))
                            .font(.ui(11, .semibold)).foregroundStyle(PermissionColor.secondary)
                        Spacer()
                        Text("\(requests.count)")
                            .font(.tabular(10, .semibold)).foregroundStyle(PermissionColor.signal)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(PermissionColor.signal.opacity(0.16), in: Capsule())
                    }.padding(.horizontal, 4).padding(.bottom, 8)
                    VStack(spacing: 2) {
                        ForEach(requests) { request in
                            PermissionClosedRow(request: request, onSelect: { onSelectRequest(request.id) })
                                .accessibilityIdentifier("island-event-permission-\(request.id)")
                                .help(L10n.text("展开请求详情", "Show request details"))
                        }
                    }
                }
            }

            if !replies.isEmpty {
                VStack(spacing: 2) {
                    ForEach(replies) { reply in
                        CompletionClosedRow(event: reply, onSelect: { onSelectRequest(reply.id) })
                    }
                }
            }
        }
        .foregroundStyle(Theme.island.text)
        .accessibilityIdentifier("island-event-panel")
    }
}

private struct CompletionClosedRow: View {
    let event: SessionCompletion
    let onSelect: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                AgentLogo(vendor: event.agentVendor, size: 13).opacity(0.8)
                Text(event.agentVendor).font(.ui(12, .medium)).lineLimit(1).minimumScaleFactor(0.8)
                HStack(spacing: 3) {
                    Image(systemName: "text.bubble").font(.system(size: 8, weight: .bold))
                    Text(L10n.text("有新回复", "New reply")).font(.ui(10, .bold))
                }
                .foregroundStyle(Color(IslandAlert.turnAccent))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color(IslandAlert.turnAccent).opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                .fixedSize()
                Text(event.task).font(.ui(11)).foregroundStyle(Theme.island.secondary).lineLimit(1)
                Spacer(minLength: 6)
                Text(event.completedAt.formatted(date: .omitted, time: .shortened))
                    .font(.tabular(11)).foregroundStyle(Theme.island.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Theme.island.segmentBackground : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityIdentifier("island-event-reply-\(event.id)")
        .accessibilityLabel(L10n.text("打开 \(event.agentVendor) 的回复：\(event.task)",
                                      "Open \(event.agentVendor) reply: \(event.task)"))
        .help(L10n.text("展开回复与会话操作", "Show reply and session actions"))
    }
}

struct IslandAlertInlineView: View {
    let alert: IslandAlert
    let onOpen: () -> Void
    let onDecide: (PermissionDecision) -> Void
    var onOpenSession: () -> Void = {}
    var onOpenUsage: () -> Void = {}
    var sessionNavigationFailed = false
    var waitingRequests: [PermissionRequest] = []
    var body: some View {
        switch alert {
        case .permission(let request): PermissionAlertInlineView(request: request, onDecide: onDecide,
                                                                 waiting: max(1, waitingRequests.count))
        case .quota(let event): QuotaAlertInlineView(alert: event, onOpen: onOpen)
        case .resetCredits(let event): ResetCreditAlertInlineView(grant: event, onOpen: onOpen)
        case .completion(let event):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TurnEndedSymbol()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("\(event.agentVendor) · 有新回复", "\(event.agentVendor) · New reply"))
                            .font(.ui(12, .medium)).foregroundStyle(Color(alert.accent))
                        Text(event.task).font(.ui(11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        if let message = event.message {
                            Text(message).font(.ui(11)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                        }
                    }
                    Spacer()
                }
                CompletionAlertActions(hasSession: event.navigationTarget != nil,
                                       navigationFailed: sessionNavigationFailed,
                                       onOpenSession: onOpenSession, onOpenUsage: onOpenUsage)
            }.foregroundStyle(.white).padding(.vertical, 8)
        }
    }
}

/// The same destinations in the standalone reply card and the usage panel's inline reminder.
private struct CompletionAlertActions: View {
    let hasSession: Bool
    let navigationFailed: Bool
    let onOpenSession: () -> Void
    let onOpenUsage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if navigationFailed && hasSession {
                Text(L10n.text("无法回到会话，请重试或查看 Token 用量", "Couldn't return to session. Retry or view token usage."))
                    .font(.ui(11)).foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            } else if !hasSession {
                Text(L10n.text("暂时无法回到原会话", "Session return unavailable"))
                    .font(.ui(11)).foregroundStyle(.white.opacity(0.5))
            }
            HStack(spacing: 6) {
                Button(action: onOpenUsage) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.xaxis").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.island.secondary)
                        Text(L10n.text("查看 Token 用量", "View token usage"))
                            .font(.ui(11, .medium)).lineLimit(1)
                    }
                    .foregroundStyle(Theme.island.secondary)
                    .padding(.horizontal, 9).frame(height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.island.cardBorder, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("island-alert-openTokenUsage")
                Spacer(minLength: 8)
                if hasSession {
                    Button(action: onOpenSession) {
                        HStack(spacing: 4) {
                            Image(systemName: navigationFailed ? "arrow.clockwise" : "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                            Text(navigationFailed ? L10n.text("重试会话跳转", "Retry session")
                                 : L10n.text("回到会话", "Return to session"))
                                .font(.ui(11, .medium)).lineLimit(1)
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9).frame(height: 22)
                        .background(Color(IslandAlert.turnAccent), in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("island-alert-openSession")
                }
            }.buttonStyle(.plain)
        }
    }
}

private struct TurnEndedSymbol: View {
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: "text.bubble")
            .symbolRenderingMode(.palette)
            .font(.system(size: size, weight: .semibold)).foregroundStyle(Color(IslandAlert.turnAccent))
    }
}

/// The whole reply, scrolling once it is taller than the card should grow, and selectable for copying.
struct ReplyText: View {
    let text: String
    var maxHeight: CGFloat = 280

    var body: some View {
        // Like a chat: it opens at the end of the reply, beside the field, and stays there as the reply changes.
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    Text(Self.rendered(text))
                        .font(.ui(12)).foregroundStyle(.white.opacity(0.82))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Color.clear.frame(height: 1).id(Self.end)
                }
            }
            .onAppear { scrollToEnd(reader) }
            .onChange(of: text) { _, _ in scrollToEnd(reader) }
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("island-alert-reply")
    }

    private static let end = "reply-end"

    private func scrollToEnd(_ reader: ScrollViewProxy) {
        reader.scrollTo(Self.end, anchor: .bottom)
        // Once more after layout settles: the first pass can run before the text has its final height.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            reader.scrollTo(Self.end, anchor: .bottom)
        }
    }

    /// Replies are Markdown; inline styles render, and the line structure (lists, code blocks) is kept as written.
    static func rendered(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// Answers the session from the card: Return sends, and the next reply arrives as the session's next reminder.
struct QuickReplyBar: View {
    /// The session's own client, "Claude" or "Codex".
    let vendor: String
    let sessionID: String
    /// The name shown to the user.
    let agentName: String
    /// Takes the keyboard as soon as it shows: for a chat the user just opened, not for a reminder that arrived.
    var focusesOnAppear = false
    @Environment(\.islandTyping) private var islandTyping
    @State private var draft = ""
    @State private var state: SendState = .idle
    @State private var fieldID = UUID()

    enum SendState: Equatable {
        case idle, sending
        case sent(QuickReply.Delivery)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                IslandTextField(
                    text: draft,
                    placeholder: L10n.text("回复 \(agentName)…（回车发送）", "Reply to \(agentName)… (Return sends)"),
                    onChange: { draft = $0 },
                    onSubmit: send,
                    onTyping: islandTyping,
                    focusesOnAppear: focusesOnAppear
                )
                .id(fieldID)
                .frame(height: 16)
                .accessibilityIdentifier("island-quick-reply-field")
                Button(action: send) {
                    Image(systemName: state == .sending ? "ellipsis" : "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 22, height: 22)
                        .background(canSend ? Theme.accent : Color.white.opacity(0.25), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityIdentifier("island-quick-reply-send")
                .help(L10n.text("发送", "Send"))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.12), lineWidth: 1))
            if let note {
                Text(note).font(.ui(11)).foregroundStyle(noteColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var canSend: Bool { state != .sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var note: String? {
        switch state {
        case .idle, .sending: return nil
        case .sent(.live): return L10n.text("已发送到 \(agentName)，回复好了会显示在这里。",
                                           "Sent to \(agentName); its reply will show here.")
        case .sent(.background): return L10n.text("已在后台发送，回复好了会显示在这里（\(agentName) 窗口不会实时显示这一轮）。",
                                                 "Sent in the background; the reply will show here (the \(agentName) window won't show this turn live).")
        case .failed(let reason): return reason
        }
    }

    private var noteColor: Color {
        if case .failed = state { return Color(hex: 0xff8a7a) }
        return .white.opacity(0.55)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !text.isEmpty else { return }
        state = .sending
        Task { @MainActor in
            do {
                let delivery = try await QuickReply.send(text, vendor: vendor, sessionID: sessionID)
                draft = ""
                fieldID = UUID()
                state = .sent(delivery)
            } catch let failure as QuickReply.Failure {
                state = .failed(failure.message)
            } catch {
                state = .failed(L10n.text("发送失败：\(error.localizedDescription)", "Not sent: \(error.localizedDescription)"))
            }
        }
    }
}
