//
//  AIUsageDetail.swift
//  Light Stats
//

import SwiftUI

struct AIUsageDetail: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject private var credentials = AIUsageCredentialStore.shared
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.theme) private var theme

    private var localRows: [AIUsageProviderRow] {
        AIUsageCatalog.providers.filter { $0.credential != .apiToken }
    }

    private var tokenRows: [AIUsageProviderRow] {
        AIUsageCatalog.providers.filter { $0.credential == .apiToken }
    }

    var body: some View {
        SettingsDetailScaffold("settings.aiUsage".localized) {
            providerSection(title: "aiUsage.group.local".localized, hint: nil, rows: localRows)
            providerSection(
                title: "aiUsage.group.token".localized,
                hint: "aiUsage.token.hint".localized,
                rows: tokenRows
            )
        }
        .task { await credentials.refreshPresence() }
    }

    @ViewBuilder
    private func providerSection(title: String, hint: String?, rows: [AIUsageProviderRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.inkPrimary)
                if let hint {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.inkSecondary)
                }
            }
            SettingsGroup {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { rowDivider() }
                    ProviderUsageRow(row: row, settings: settings, credentials: credentials)
                }
            }
        }
    }
}

private struct ProviderUsageRow: View {
    @Environment(\.theme) private var theme
    let row: AIUsageProviderRow
    @ObservedObject var settings: SettingsManager
    @ObservedObject var credentials: AIUsageCredentialStore
    @State private var draft = ""
    @State private var edited = false
    @State private var copied = false
    @State private var copyGeneration = 0
    @State private var saved = false
    @State private var saveGeneration = 0

    private var enabled: Bool { settings.isAIProviderEnabled(row.id) }
    private var hasToken: Bool { credentials.tokenPresent.contains(row.id) }
    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool {
        if !trimmed.isEmpty { return true }
        return edited && trimmed.isEmpty && hasToken
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 10) {
                Text(row.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.inkPrimary)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 12)
                    .layoutPriority(0)
                if enabled, row.credential == .apiToken {
                    tokenField
                        .frame(width: max(160, (geo.size.width - 32) * 0.45))
                        .layoutPriority(1)
                    copyButton
                    Button(action: commit) {
                        MaxContentLabel(
                            candidates: ["aiUsage.token.save".localized, "aiUsage.token.saved".localized],
                            current: saved ? "aiUsage.token.saved".localized : "aiUsage.token.save".localized
                        )
                    }
                    .controlSize(.small)
                    .disabled(!canSave)
                    .fixedSize()
                    .layoutPriority(2)
                }
                SettingsToggle(isOn: Binding(
                    get: { settings.isAIProviderEnabled(row.id) },
                    set: { settings.setAIProviderEnabled(row.id, $0) }
                ))
                .fixedSize()
                .layoutPriority(2)
                if row.supportsWarmup {
                    renewSlot
                }
            }
            .padding(.horizontal, 16)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .frame(height: 48)
    }

    private var copyButton: some View {
        Button(action: copyToken) {
            MaxContentLabel(
                candidates: [
                    "aiUsage.token.copy".localized,
                    "aiUsage.token.copied".localized
                ],
                current: copied ? "aiUsage.token.copied".localized : "aiUsage.token.copy".localized
            )
        }
        .controlSize(.small)
        .disabled(!hasToken)
        .opacity(hasToken ? 1 : 0)
        .fixedSize()
        .layoutPriority(2)
    }

    private var renewSlot: some View {
        Button(action: toggleWarmup) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(enabled && warmupOn ? 1 : 0)
                Text("aiUsage.autoRefresh.short".localized)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(theme.inkPrimary)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0)
        .layoutPriority(2)
    }

    private var warmupOn: Bool {
        switch row.id {
        case .claude: return settings.autoRefreshClaudeEnabled
        case .codex: return settings.autoRefreshCodexEnabled
        default: return false
        }
    }

    private func toggleWarmup() {
        switch row.id {
        case .claude: settings.autoRefreshClaudeEnabled.toggle()
        case .codex: settings.autoRefreshCodexEnabled.toggle()
        default: break
        }
    }

    private var tokenField: some View {
        ZStack(alignment: .leading) {
            SecureField("", text: $draft, prompt: Text(promptText).font(.system(size: 11)))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onSubmit(commit)
                .onChange(of: draft) { _, _ in edited = true }
            if hasToken && draft.isEmpty {
                Text("••••••••")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Cookie-based providers need a `Cookie:` header rather than an API key; the prompt is
    /// the only place the user sees that before the first failed fetch.
    private var promptText: String {
        guard !hasToken, let key = row.tokenHintKey else { return "" }
        return key.localized
    }

    private func copyToken() {
        copyGeneration += 1
        let generation = copyGeneration
        Task {
            guard await credentials.copyToken(for: row.id) else { return }
            copied = true
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copyGeneration == generation {
                copied = false
            }
        }
    }

    private func commit() {
        if trimmed.isEmpty {
            guard hasToken, edited else { return }
            Task {
                if await credentials.clear(id: row.id) {
                    draft = ""
                    edited = false
                } else {
                    showSaveFailure()
                }
            }
            return
        }
        let token = trimmed
        Task {
            guard await credentials.save(token: token, for: row.id) else {
                showSaveFailure()
                return
            }
            draft = ""
            edited = false
            confirmSaved()
        }
    }

    /// 保存成功：按钮短暂显示「已保存」并弹一条 toast，与复制按钮的「已复制」一致。
    /// 之前这里两条路径都没有任何反馈，失败还静默 return，用户看到的就是「点了没反应」。
    private func confirmSaved() {
        saveGeneration += 1
        let generation = saveGeneration
        saved = true
        ToastCenter.shared.show(
            message: "aiUsage.token.saved".localized,
            systemImage: "checkmark.circle.fill",
            tint: .green
        )
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if saveGeneration == generation { saved = false }
        }
    }

    private func showSaveFailure() {
        ToastCenter.shared.show(
            message: "aiUsage.token.saveFailed".localized,
            systemImage: "exclamationmark.triangle.fill",
            tint: .orange
        )
    }
}

/// Hugs the longest candidate so swapping labels cannot resize the control.
private struct MaxContentLabel: View {
    let candidates: [String]
    let current: String
    var fontSize: CGFloat = 13

    var body: some View {
        ZStack {
            ForEach(candidates, id: \.self) { text in
                Text(text)
                    .font(.system(size: fontSize))
                    .hidden()
            }
            Text(current)
                .font(.system(size: fontSize))
        }
        .lineLimit(1)
        .fixedSize()
    }
}
