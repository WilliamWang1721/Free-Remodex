// FILE: SettingsView.swift
// Purpose: Settings for Local Mode (Codex runs on user's Mac, relay WebSocket).
// Layer: View
// Exports: SettingsView

import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(CodexService.self) private var codex

    @AppStorage("codex.appFontStyle") private var appFontStyleRawValue = AppFont.defaultStoredStyleRawValue
    @State private var isShowingMacNameSheet = false
    @State private var isRefreshingModels = false
    @State private var lastModelsRefreshAt: Date?

    private let runtimeAutoValue = "__AUTO__"
    private let runtimeNormalValue = "__NORMAL__"
    private let settingsAccentColor = Color(.plan)

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SettingsArchivedChatsCard()
                SettingsAppearanceCard(appFontStyle: appFontStyleBinding)
                SettingsNotificationsCard()
                SettingsGPTAccountCard()
                SettingsSelfHostedBuildCard()
                SettingsBridgeVersionCard()
                runtimeDefaultsSection
                SettingsCustomModelsCard()
                SettingsAboutCard()
                SettingsUsageCard()
                connectionSection
            }
            .padding()
        }
        .font(AppFont.body())
        .navigationTitle("Settings")
        .sheet(isPresented: $isShowingMacNameSheet) {
            if let trustedPairPresentation = codex.trustedPairPresentation {
                SettingsMacNameSheet(
                    nickname: sidebarMacNicknameBinding(for: trustedPairPresentation),
                    currentName: trustedPairPresentation.name,
                    systemName: trustedPairPresentation.systemName ?? trustedPairPresentation.name
                )
            }
        }
    }

    private var appFontStyleBinding: Binding<AppFont.Style> {
        Binding(
            get: { AppFont.Style(rawValue: appFontStyleRawValue) ?? AppFont.defaultStyle },
            set: { appFontStyleRawValue = $0.rawValue }
        )
    }

    // MARK: - Runtime defaults

    @ViewBuilder private var runtimeDefaultsSection: some View {
        SettingsCard(title: "Runtime defaults") {
            HStack {
                Text("Model")
                Spacer()
                Picker("Model", selection: runtimeModelSelection) {
                    Text("Auto").tag(runtimeAutoValue)
                    ForEach(runtimeModelOptions, id: \.id) { model in
                        Text(TurnComposerMetaMapper.modelTitle(for: model))
                            .tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(settingsAccentColor)
            }

            Text("Refresh the latest model list from the Codex runtime currently running on your Mac (Codex App / CLI).")
                .font(AppFont.caption())
                .foregroundStyle(.secondary)

            HStack {
                Text("Detected")
                Spacer()
                Text("\(runtimeModelOptions.count) models")
                    .foregroundStyle(.secondary)
            }

            if let lastModelsRefreshAt {
                HStack {
                    Text("Last refresh")
                    Spacer()
                    Text(lastModelsRefreshAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }

            SettingsButton(
                isRefreshingModels ? "Refreshing Models..." : "Refresh Models From Mac",
                isLoading: isRefreshingModels
            ) {
                refreshModelsFromMac()
            }
            .disabled(!codex.isConnected || isRefreshingModels)

            if !codex.isConnected {
                Text("Connect to your Mac before refreshing the model list.")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }

            if let modelsErrorMessage = codex.modelsErrorMessage,
               !modelsErrorMessage.isEmpty {
                Text(modelsErrorMessage)
                    .font(AppFont.caption())
                    .foregroundStyle(.red)
            }

            HStack {
                Text("Reasoning")
                Spacer()
                Picker("Reasoning", selection: runtimeReasoningSelection) {
                    Text("Auto").tag(runtimeAutoValue)
                    ForEach(runtimeReasoningOptions, id: \.id) { option in
                        Text(option.title).tag(option.effort)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(settingsAccentColor)
                .disabled(runtimeReasoningOptions.isEmpty)
            }

            HStack {
                Text("Speed")
                Spacer()
                Picker("Speed", selection: runtimeServiceTierSelection) {
                    Text("Normal").tag(runtimeNormalValue)
                    ForEach(CodexServiceTier.allCases, id: \.rawValue) { tier in
                        Text(tier.displayName).tag(tier.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(settingsAccentColor)
            }

            HStack {
                Text("Access")
                Spacer()
                Picker("Access", selection: runtimeAccessSelection) {
                    ForEach(CodexAccessMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(settingsAccentColor)
            }
        }
    }

    // MARK: - Connection

    @ViewBuilder private var connectionSection: some View {
        SettingsCard(title: "Connection") {
            if let trustedPairPresentation = codex.trustedPairPresentation {
                SettingsTrustedMacCard(
                    presentation: trustedPairPresentation,
                    connectionStatusLabel: connectionStatusLabel,
                    onEditName: {
                        isShowingMacNameSheet = true
                    }
                )
            } else {
                Text("No paired Mac")
                    .font(AppFont.subheadline(weight: .semibold))
                    .foregroundStyle(.primary)
            }

            if connectionPhaseShowsProgress {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(connectionProgressLabel)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                }
            }

            if case .retrying(_, let message) = codex.connectionRecoveryState,
               !message.isEmpty {
                Text(message)
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }

            if let error = codex.lastErrorMessage, !error.isEmpty {
                Text(error)
                    .font(AppFont.caption())
                    .foregroundStyle(.red)
            }

            if codex.isConnected {
                SettingsButton("Disconnect", role: .destructive) {
                    HapticFeedback.shared.triggerImpactFeedback()
                    disconnectRelay()
                }
            } else if codex.hasTrustedMacReconnectCandidate {
                SettingsButton("Forget Pair", role: .destructive) {
                    HapticFeedback.shared.triggerImpactFeedback()
                    codex.forgetTrustedMac()
                }
            }
        }
    }

    private var connectionPhaseShowsProgress: Bool {
        switch codex.connectionPhase {
        case .connecting, .loadingChats, .syncing:
            return true
        case .offline, .connected:
            return false
        }
    }

    private var connectionStatusLabel: String {
        switch codex.connectionPhase {
        case .offline:
            return "offline"
        case .connecting:
            return "connecting"
        case .loadingChats:
            return "loading chats"
        case .syncing:
            return "syncing"
        case .connected:
            return "connected"
        }
    }

    private var connectionProgressLabel: String {
        switch codex.connectionPhase {
        case .connecting:
            return "Connecting to relay..."
        case .loadingChats:
            return "Loading chats..."
        case .syncing:
            return "Syncing workspace..."
        case .offline, .connected:
            return ""
        }
    }

    // MARK: - Actions

    private func disconnectRelay() {
        Task { @MainActor in
            await codex.disconnect()
            codex.clearSavedRelaySession()
        }
    }

    private func refreshModelsFromMac() {
        guard codex.isConnected, !isRefreshingModels else { return }
        HapticFeedback.shared.triggerImpactFeedback(style: .light)
        isRefreshingModels = true

        Task {
            defer {
                Task { @MainActor in
                    isRefreshingModels = false
                }
            }

            do {
                try await codex.listModels()
                await MainActor.run {
                    lastModelsRefreshAt = Date()
                }
            } catch {
                // CodexService already exposes a user-facing modelsErrorMessage.
            }
        }
    }

    // MARK: - Runtime bindings

    private var runtimeModelOptions: [CodexModelOption] {
        TurnComposerMetaMapper.orderedModels(from: codex.mergedAvailableModels())
    }

    private var runtimeReasoningOptions: [TurnComposerReasoningDisplayOption] {
        TurnComposerMetaMapper.reasoningDisplayOptions(
            from: codex.supportedReasoningEffortsForSelectedModel()
        )
    }

    private var runtimeModelSelection: Binding<String> {
        Binding(
            get: { codex.selectedModelOption()?.id ?? runtimeAutoValue },
            set: { selection in
                codex.setSelectedModelId(selection == runtimeAutoValue ? nil : selection)
            }
        )
    }

    private var runtimeReasoningSelection: Binding<String> {
        Binding(
            get: { codex.selectedReasoningEffort ?? runtimeAutoValue },
            set: { selection in
                codex.setSelectedReasoningEffort(selection == runtimeAutoValue ? nil : selection)
            }
        )
    }

    private var runtimeAccessSelection: Binding<CodexAccessMode> {
        Binding(
            get: { codex.selectedAccessMode },
            set: { codex.setSelectedAccessMode($0) }
        )
    }

    private var runtimeServiceTierSelection: Binding<String> {
        Binding(
            get: { codex.selectedServiceTier?.rawValue ?? runtimeNormalValue },
            set: { selection in
                codex.setSelectedServiceTier(
                    selection == runtimeNormalValue ? nil : CodexServiceTier(rawValue: selection)
                )
            }
        )
    }

    // Writes nicknames against the active trusted Mac so switching pairs does not reuse the wrong alias.
    private func sidebarMacNicknameBinding(for presentation: CodexTrustedPairPresentation) -> Binding<String> {
        Binding(
            get: { SidebarMacNicknameStore.nickname(for: presentation.deviceId) },
            set: { SidebarMacNicknameStore.setNickname($0, for: presentation.deviceId) }
        )
    }
}

private struct SettingsSelfHostedBuildCard: View {
    var body: some View {
        SettingsCard(title: "Self-Hosted Build") {
            Text("In-app purchases are removed in this self-hosted build so it can run under a Personal Team profile.")
                .font(AppFont.caption())
                .foregroundStyle(.secondary)

            HStack {
                Text("Status")
                Spacer()
                Text("Unlocked")
                    .foregroundStyle(.green)
            }
        }
    }
}

private enum SettingsCustomModelReasoningMode: String, CaseIterable, Identifiable {
    case inheritDefault = "inherit_default"
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inheritDefault:
            return "Inherit Default"
        case .custom:
            return "Custom"
        }
    }

    var subtitle: String {
        switch self {
        case .inheritDefault:
            return "Use the built-in OpenAI-style reasoning levels."
        case .custom:
            return "Define the raw level names and labels this model should expose."
        }
    }
}

private struct SettingsCustomModelReasoningLevelDraft: Identifiable {
    let id: UUID
    var effort: String
    var displayName: String

    init(id: UUID = UUID(), effort: String = "", displayName: String = "") {
        self.id = id
        self.effort = effort
        self.displayName = displayName
    }
}

private struct SettingsCustomModelDraft {
    var editingModelID: String?
    var model = ""
    var displayName = ""
    var reasoningMode: SettingsCustomModelReasoningMode = .inheritDefault
    var defaultReasoningEffort = CodexModelOption.inheritedDefaultReasoningEffort
    var reasoningLevels: [SettingsCustomModelReasoningLevelDraft] = []

    init() {}

    init(modelOption: CodexModelOption) {
        editingModelID = modelOption.id
        model = modelOption.model
        displayName = modelOption.displayName
        defaultReasoningEffort = modelOption.defaultReasoningEffort ?? CodexModelOption.inheritedDefaultReasoningEffort

        if modelOption.inheritsOpenAIDefaultReasoningEfforts || modelOption.supportedReasoningEfforts.isEmpty {
            reasoningMode = .inheritDefault
            reasoningLevels = []
        } else {
            reasoningMode = .custom
            reasoningLevels = modelOption.supportedReasoningEfforts.map { option in
                SettingsCustomModelReasoningLevelDraft(
                    effort: option.reasoningEffort,
                    displayName: option.displayName ?? TurnComposerMetaMapper.reasoningTitle(for: option)
                )
            }
        }
    }
}

private struct SettingsCustomModelsCard: View {
    @Environment(CodexService.self) private var codex

    @State private var draft = SettingsCustomModelDraft()

    var body: some View {
        SettingsCard(title: "Custom Models") {
            Text("Add or edit models manually when your Mac-side Codex runtime supports them before the detected list catches up.")
                .font(AppFont.caption())
                .foregroundStyle(.secondary)

            TextField("Model name", text: $draft.model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppFont.mono(.subheadline))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            TextField("Display name", text: $draft.displayName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppFont.body())
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Picker("Reasoning levels", selection: $draft.reasoningMode) {
                ForEach(SettingsCustomModelReasoningMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(draft.reasoningMode.subtitle)
                .font(AppFont.caption())
                .foregroundStyle(.secondary)

            if draft.reasoningMode == .inheritDefault {
                Text("Default levels: Low, Medium, High, Extra High.")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            } else {
                customReasoningEditor
            }

            HStack(spacing: 10) {
                SettingsButton(draft.editingModelID == nil ? "Save Custom Model" : "Update Custom Model") {
                    saveDraft()
                }
                .disabled(isSaveDisabled)

                if draft.editingModelID != nil {
                    Button("Cancel") {
                        resetDraft()
                    }
                    .font(AppFont.caption(weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }

            if codex.customModelOptions.isEmpty {
                Text("No custom models added yet.")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            } else {
                ForEach(codex.customModelOptions, id: \.id) { model in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(model.displayName)
                                .font(AppFont.subheadline(weight: .semibold))
                            Spacer()
                            Button("Edit") {
                                startEditing(model)
                            }
                            .font(AppFont.caption(weight: .medium))
                            Button("Delete", role: .destructive) {
                                codex.removeCustomModel(id: model.id)
                                if draft.editingModelID == model.id {
                                    resetDraft()
                                }
                            }
                            .font(AppFont.caption(weight: .medium))
                        }

                        Text(model.model)
                            .font(AppFont.mono(.caption))
                            .foregroundStyle(.secondary)

                        Text(reasoningSummary(for: model))
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .onChange(of: draft.reasoningMode) { _, newValue in
            if newValue == .custom, draft.reasoningLevels.isEmpty {
                addReasoningLevel()
            }
        }
    }

    @ViewBuilder private var customReasoningEditor: some View {
        if draft.reasoningLevels.isEmpty {
            Text("No custom reasoning levels yet.")
                .font(AppFont.caption())
                .foregroundStyle(.secondary)
        }

        ForEach(draft.reasoningLevels.indices, id: \.self) { index in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Level \(index + 1)")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove", role: .destructive) {
                        removeReasoningLevel(at: index)
                    }
                    .font(AppFont.caption(weight: .medium))
                }

                TextField("Level name (for example: extra_high)", text: $draft.reasoningLevels[index].effort)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(AppFont.mono(.caption))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                TextField("Display name (for example: Extra High)", text: $draft.reasoningLevels[index].displayName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .font(AppFont.body())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }

        Button("Add Reasoning Level") {
            addReasoningLevel()
        }
        .font(AppFont.caption(weight: .medium))
    }

    private var trimmedModel: String {
        draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDisplayName: String {
        draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedReasoningLevels: [CodexReasoningEffortOption] {
        var normalizedLevels: [CodexReasoningEffortOption] = []
        var seenEfforts: Set<String> = []

        for level in draft.reasoningLevels {
            let normalizedEffort = level.effort.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedDisplayName = level.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let lookupKey = normalizedEffort.lowercased()
            guard !normalizedEffort.isEmpty,
                  !normalizedDisplayName.isEmpty,
                  !seenEfforts.contains(lookupKey) else {
                continue
            }

            seenEfforts.insert(lookupKey)
            normalizedLevels.append(
                CodexReasoningEffortOption(
                    reasoningEffort: normalizedEffort,
                    displayName: normalizedDisplayName
                )
            )
        }

        return normalizedLevels
    }

    private var resolvedDefaultReasoningEffort: String? {
        if draft.reasoningMode == .inheritDefault {
            return CodexModelOption.inheritedDefaultReasoningEffort
        }

        let normalizedDefault = draft.defaultReasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedReasoningLevels.contains(where: { $0.reasoningEffort == normalizedDefault }) {
            return normalizedDefault
        }
        return normalizedReasoningLevels.first?.reasoningEffort
    }

    private var isSaveDisabled: Bool {
        if trimmedModel.isEmpty || trimmedDisplayName.isEmpty {
            return true
        }

        if draft.reasoningMode == .custom {
            return normalizedReasoningLevels.isEmpty
        }

        return false
    }

    private func addReasoningLevel() {
        draft.reasoningLevels.append(SettingsCustomModelReasoningLevelDraft())
    }

    private func removeReasoningLevel(at index: Int) {
        guard draft.reasoningLevels.indices.contains(index) else {
            return
        }
        let removedLevel = draft.reasoningLevels.remove(at: index)
        if draft.defaultReasoningEffort == removedLevel.effort {
            draft.defaultReasoningEffort = normalizedReasoningLevels.first?.reasoningEffort ?? ""
        }
    }

    private func resetDraft() {
        draft = SettingsCustomModelDraft()
    }

    private func startEditing(_ model: CodexModelOption) {
        draft = SettingsCustomModelDraft(modelOption: model)
        if draft.reasoningMode == .custom, draft.reasoningLevels.isEmpty {
            addReasoningLevel()
        }
        HapticFeedback.shared.triggerImpactFeedback(style: .light)
    }

    private func reasoningSummary(for model: CodexModelOption) -> String {
        if model.inheritsOpenAIDefaultReasoningEfforts {
            return "Reasoning: OpenAI/default levels"
        }

        let labels = model.supportedReasoningEfforts.compactMap { option in
            let displayName = option.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let displayName, !displayName.isEmpty {
                return displayName
            }
            return TurnComposerMetaMapper.reasoningTitle(for: option)
        }
        if labels.isEmpty {
            return "Reasoning: none configured"
        }

        return "Reasoning: " + labels.joined(separator: ", ")
    }

    private func saveDraft() {
        let model = trimmedModel
        let displayName = trimmedDisplayName
        guard !model.isEmpty, !displayName.isEmpty else {
            return
        }

        codex.saveCustomModel(
            model: model,
            displayName: displayName,
            inheritsOpenAIDefaultReasoningEfforts: draft.reasoningMode == .inheritDefault,
            supportedReasoningEfforts: draft.reasoningMode == .inheritDefault ? [] : normalizedReasoningLevels,
            defaultReasoningEffort: resolvedDefaultReasoningEffort
        )
        resetDraft()
        HapticFeedback.shared.triggerImpactFeedback(style: .light)
    }
}

// MARK: - Reusable card / button components

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemFill).opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

struct SettingsButton: View {
    let title: String
    var role: ButtonRole?
    var isLoading: Bool = false
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    Text(title)
                }
            }
            .font(AppFont.subheadline(weight: .medium))
            .foregroundStyle(role == .destructive ? .red : (role == .cancel ? .secondary : .primary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                (role == .destructive ? Color.red : Color.primary).opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Extracted independent section views

private struct SettingsUsageCard: View {
    @Environment(CodexService.self) private var codex
    @Environment(\.scenePhase) private var scenePhase

    @State private var isRefreshing = false

    var body: some View {
        SettingsCard(title: "Usage") {
            UsageStatusSummaryContent(
                contextWindowUsage: activeThreadContextWindowUsage,
                rateLimitBuckets: codex.rateLimitBuckets,
                isLoadingRateLimits: codex.isLoadingRateLimits,
                rateLimitsErrorMessage: codex.rateLimitsErrorMessage,
                contextPlacement: .bottom,
                refreshControl: UsageStatusRefreshControl(
                    title: "Refresh",
                    isRefreshing: isRefreshing,
                    action: refreshStatus
                )
            )

            if activeThreadID == nil {
                Text("Open a chat to populate the current thread context window here.")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await refreshStatusIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await refreshStatusIfNeeded()
            }
        }
        .onChange(of: activeThreadID) { _, _ in
            Task {
                await refreshStatusIfNeeded()
            }
        }
    }

    private var activeThreadID: String? {
        let trimmed = codex.activeThreadId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return nil
    }

    private var activeThreadContextWindowUsage: ContextWindowUsage? {
        guard let activeThreadID else { return nil }
        return codex.contextWindowUsageByThread[activeThreadID]
    }

    private func refreshStatus() {
        guard !isRefreshing else { return }
        HapticFeedback.shared.triggerImpactFeedback(style: .light)
        isRefreshing = true

        Task {
            await refreshStatusData()
            await MainActor.run {
                isRefreshing = false
            }
        }
    }

    private func refreshStatusIfNeeded() async {
        guard !isRefreshing else { return }
        guard codex.shouldAutoRefreshUsageStatus(threadId: activeThreadID) else { return }

        await MainActor.run {
            isRefreshing = true
        }
        await refreshStatusData()
        await MainActor.run {
            isRefreshing = false
        }
    }

    // Loads account-wide windows globally and thread context from the active chat when available.
    private func refreshStatusData() async {
        await codex.refreshUsageStatus(threadId: activeThreadID)
    }
}

private struct SettingsAppearanceCard: View {
    @Binding var appFontStyle: AppFont.Style
    @AppStorage("codex.useLiquidGlass") private var useLiquidGlass = true
    private let settingsAccentColor = Color(.plan)

    var body: some View {
        SettingsCard(title: "Appearance") {
            HStack {
                Text("Font")
                Spacer()
                Picker("Font", selection: $appFontStyle) {
                    ForEach(AppFont.Style.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(settingsAccentColor)
            }

            Text(appFontStyle.subtitle)
                .font(AppFont.caption())
                .foregroundStyle(.secondary)

            if GlassPreference.isSupported {
                Divider()

                Toggle("Liquid Glass", isOn: $useLiquidGlass)
                    .tint(settingsAccentColor)

                Text(useLiquidGlass
                     ? "Liquid Glass effects are enabled."
                     : "Using solid material fallback.")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsNotificationsCard: View {
    @Environment(CodexService.self) private var codex
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        SettingsCard(title: "Notifications") {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge")
                    .foregroundStyle(.primary)
                Text("Status")
                Spacer()
                Text(statusLabel)
                    .foregroundStyle(.secondary)
            }

            Text("Used for local alerts when a run finishes while the app is in background.")
                .font(AppFont.caption())
                .foregroundStyle(.secondary)

            if codex.notificationAuthorizationStatus == .notDetermined {
                SettingsButton("Allow notifications") {
                    HapticFeedback.shared.triggerImpactFeedback()
                    Task {
                        await codex.requestNotificationPermission()
                    }
                }
            }

            if codex.notificationAuthorizationStatus == .denied {
                SettingsButton("Open iOS Settings") {
                    HapticFeedback.shared.triggerImpactFeedback()
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .task {
            await codex.refreshManagedNotificationRegistrationState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                return
            }
            Task {
                await codex.refreshManagedNotificationRegistrationState()
            }
        }
    }

    private var statusLabel: String {
        switch codex.notificationAuthorizationStatus {
        case .authorized: "Authorized"
        case .denied: "Denied"
        case .provisional: "Provisional"
        case .ephemeral: "Ephemeral"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }
}

private struct SettingsGPTAccountCard: View {
    @Environment(CodexService.self) private var codex
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLoggingOut = false
    @State private var isShowingMacLoginInfo = false

    var body: some View {
        let snapshot = codex.gptAccountSnapshot

        SettingsCard(title: "ChatGPT") {
            HStack(spacing: 10) {
                Image(systemName: statusIconName(for: snapshot))
                    .foregroundStyle(statusIconColor(for: snapshot))
                Text("Status")
                Spacer()
                SettingsStatusPill(label: snapshot.statusLabel)
            }

            if let detail = snapshot.detailText {
                Text(detail)
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }

            if let hint = hintText(for: snapshot) {
                Text(hint)
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = codex.gptAccountErrorMessage,
               !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(errorMessage)
                    .font(AppFont.caption())
                    .foregroundStyle(.red)
            }

            // Keeps the reauth state compact while preserving access to the Mac sign-in explainer.
            if !snapshot.isAuthenticated {
                HStack {
                    Spacer()
                    Button {
                        HapticFeedback.shared.triggerImpactFeedback(style: .light)
                        isShowingMacLoginInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(AppFont.subheadline(weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("How ChatGPT voice sign-in works")
                }
            }

            if snapshot.canLogout {
                SettingsButton("Log out", role: .destructive, isLoading: isLoggingOut) {
                    HapticFeedback.shared.triggerImpactFeedback()
                    logout()
                }
            }
        }
        .task {
            await codex.refreshGPTAccountState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await codex.refreshGPTAccountState()
            }
        }
        .sheet(isPresented: $isShowingMacLoginInfo) {
            SettingsGPTMacLoginSheet()
        }
    }

    private func hintText(for snapshot: CodexGPTAccountSnapshot) -> String? {
        if snapshot.needsReauth { return "Voice on this bridge needs a fresh ChatGPT sign-in on your Mac." }
        if snapshot.isAuthenticated && snapshot.isVoiceTokenReady { return nil }
        if snapshot.isAuthenticated { return "Waiting for voice sync..." }
        if snapshot.hasActiveLogin && codex.isConnected { return "Finish the ChatGPT sign-in flow in the browser on your Mac." }
        if snapshot.hasActiveLogin { return "Reconnect to your bridge to finish sign-in on your Mac." }
        if !codex.isConnected { return "Connect to your bridge first." }
        return "ChatGPT voice uses the account already signed in on your Mac."
    }

    private func statusIconName(for snapshot: CodexGPTAccountSnapshot) -> String {
        switch snapshot.status {
        case .authenticated:
            return snapshot.needsReauth ? "exclamationmark.triangle.fill" : "checkmark.shield.fill"
        case .loginPending:
            return "arrow.up.forward.app.fill"
        case .expired:
            return "exclamationmark.triangle.fill"
        case .notLoggedIn, .unknown:
            return "person.crop.circle.badge.plus"
        case .unavailable:
            return "wifi.slash"
        }
    }

    private func statusIconColor(for snapshot: CodexGPTAccountSnapshot) -> Color {
        switch snapshot.status {
        case .authenticated:
            return snapshot.needsReauth ? .orange : .green
        case .loginPending:
            return .orange
        case .expired:
            return .red
        case .notLoggedIn, .unknown, .unavailable:
            return .secondary
        }
    }

    private func logout() {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        codex.gptAccountErrorMessage = nil

        Task { @MainActor in
            await codex.logoutGPTAccount()
            await codex.refreshGPTAccountState()
            isLoggingOut = false
        }
    }
}

private struct SettingsGPTMacLoginSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.08))
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("ChatGPT voice is checked on your Mac")
                            .font(AppFont.subheadline(weight: .semibold))
                        Text("Remodex reads the ChatGPT session from your paired Mac bridge.")
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    gptSetupStep(
                        number: "1",
                        title: "Open ChatGPT on your Mac",
                        detail: "Use the Mac that is paired with this iPhone."
                    )
                    gptSetupStep(
                        number: "2",
                        title: "Sign in there",
                        detail: "Make sure the ChatGPT account you want for voice is already active on the Mac."
                    )
                    gptSetupStep(
                        number: "3",
                        title: "Come back to Remodex",
                        detail: "Keep the bridge connected and reopen Settings if the status has not refreshed yet."
                    )
                }

                Text("You do not need to start ChatGPT login from this iPhone.")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                SettingsButton("Close") {
                    dismiss()
                }
            }
            .padding(20)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .navigationTitle("Use ChatGPT on Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    // Keeps the setup instructions scannable in a compact sheet.
    private func gptSetupStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppFont.subheadline(weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsBridgeVersionCard: View {
    @Environment(CodexService.self) private var codex

    var body: some View {
        SettingsCard(title: "Bridge Version") {
            HStack(spacing: 10) {
                Text("Status")
                Spacer()
                SettingsStatusPill(label: versionStatusLabel)
            }

            settingsVersionRow(
                title: "Installed on Mac",
                value: installedVersionLabel,
                valueStyle: installedValueStyle
            )

            settingsVersionRow(
                title: "Latest available",
                value: latestVersionLabel,
                valueStyle: .primary
            )

            if let guidance = guidanceText {
                Text(guidance)
                    .font(AppFont.caption())
                    .foregroundStyle(guidanceColor)
            }
        }
    }

    private var installedVersionLabel: String {
        normalizedVersion(codex.bridgeInstalledVersion) ?? "Unknown"
    }

    private var latestVersionLabel: String {
        normalizedVersion(codex.latestBridgePackageVersion) ?? "Unknown"
    }

    private var guidanceText: String? {
        guard let installedVersion else {
            return "Connect to a Mac bridge to read the installed package version."
        }

        guard let latestVersion else {
            return "Installed version detected. The latest published package is unavailable right now."
        }

        if installedVersion == latestVersion {
            return "The installed bridge matches the latest published package."
        }

        if installedVersion.compare(latestVersion, options: .numeric) == .orderedAscending {
            return "A newer Remodex package is available on npm."
        }

        return "This Mac is running a different build than the current npm latest."
    }

    private var versionStatusLabel: String {
        guard let installedVersion else {
            return "Unknown"
        }

        guard let latestVersion else {
            return "Installed"
        }

        if installedVersion == latestVersion {
            return "Up to date"
        }

        if installedVersion.compare(latestVersion, options: .numeric) == .orderedAscending {
            return "Update available"
        }

        return "Different build"
    }

    private var guidanceColor: Color {
        guard let installedVersion,
              let latestVersion,
              installedVersion.compare(latestVersion, options: .numeric) == .orderedAscending else {
            return .secondary
        }

        return .orange
    }

    private var installedValueStyle: Color {
        guard let installedVersion,
              let latestVersion,
              installedVersion.compare(latestVersion, options: .numeric) == .orderedAscending else {
            return .primary
        }

        return .orange
    }

    private var installedVersion: String? {
        normalizedVersion(codex.bridgeInstalledVersion)
    }

    private var latestVersion: String? {
        normalizedVersion(codex.latestBridgePackageVersion)
    }

    private func normalizedVersion(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private func settingsVersionRow(title: String, value: String, valueStyle: Color) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer()
            Text(value)
                .font(AppFont.mono(.subheadline))
                .foregroundStyle(valueStyle)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

private struct SettingsArchivedChatsCard: View {
    @Environment(CodexService.self) private var codex

    private var archivedCount: Int {
        codex.threads.filter { $0.syncState == .archivedLocal }.count
    }

    var body: some View {
        SettingsCard(title: "Archived Chats") {
            NavigationLink {
                ArchivedChatsView()
            } label: {
                HStack {
                    Label("Archived Chats", systemImage: "archivebox")
                        .font(AppFont.subheadline(weight: .medium))
                    Spacer()
                    if archivedCount > 0 {
                        Text("\(archivedCount)")
                            .font(AppFont.caption(weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SettingsAboutCard: View {
    @State private var isShowingAbout = false

    var body: some View {
        SettingsCard(title: "About") {
            Text("Chats are End-to-end encrypted between your iPhone and Mac. The relay only sees ciphertext and connection metadata after the secure handshake completes.")
                .font(AppFont.caption())
                .foregroundStyle(.secondary)

            Button {
                HapticFeedback.shared.triggerImpactFeedback(style: .light)
                isShowingAbout = true
            } label: {
                settingsAccessoryRow(
                    title: "How Remodex Works",
                    leading: {
                        Image(systemName: "info.circle")
                            .font(AppFont.subheadline(weight: .medium))
                    }
                )
            }
            .buttonStyle(.plain)

            Button {
                HapticFeedback.shared.triggerImpactFeedback(style: .light)
                if let url = URL(string: "https://x.com/emanueledpt") {
                    UIApplication.shared.open(url)
                }
            } label: {
                settingsAccessoryRow(
                    title: "Chat & Support",
                    leading: {
                        Image("x-icon")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                    }
                )
            }
            .buttonStyle(.plain)

            Button {
                HapticFeedback.shared.triggerImpactFeedback(style: .light)
                UIApplication.shared.open(AppEnvironment.privacyPolicyURL)
            } label: {
                settingsAccessoryRow(
                    title: "Privacy Policy",
                    leading: {
                        Image(systemName: "hand.raised")
                            .font(AppFont.subheadline(weight: .medium))
                    }
                )
            }
            .buttonStyle(.plain)

            Button {
                HapticFeedback.shared.triggerImpactFeedback(style: .light)
                UIApplication.shared.open(AppEnvironment.termsOfUseURL)
            } label: {
                settingsAccessoryRow(
                    title: "Terms of Use",
                    leading: {
                        Image(systemName: "doc.text")
                            .font(AppFont.subheadline(weight: .medium))
                    }
                )
            }
            .buttonStyle(.plain)
        }
        .fullScreenCover(isPresented: $isShowingAbout) {
            AboutRemodexView()
        }
    }

    // Keeps settings rows visually consistent while allowing SF Symbols or asset icons.
    private func settingsAccessoryRow<Leading: View>(
        title: String,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        HStack(spacing: 8) {
            leading()
            Text(title)
                .font(AppFont.subheadline(weight: .medium))
            Spacer()
            Image(systemName: "chevron.right")
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

private struct SettingsTrustedMacCard: View {
    let presentation: CodexTrustedPairPresentation
    let connectionStatusLabel: String
    let onEditName: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.06))
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mac")
                            .font(AppFont.caption(weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text(presentation.name)
                            .font(AppFont.subheadline(weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                Spacer(minLength: 8)

                Button(action: onEditName) {
                    Image(systemName: "pencil")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit Mac name")
            }

            HStack(spacing: 8) {
                SettingsStatusPill(label: connectionStatusLabel.capitalized)

                if let title = compactTitle {
                    SettingsStatusPill(label: title)
                }
            }

            if let systemName = presentation.systemName,
               !systemName.isEmpty {
                labeledRow("System", value: systemName)
            }

            if let detail = presentation.detail,
               !detail.isEmpty {
                labeledRow("Status", value: detail)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemFill).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private var compactTitle: String? {
        let trimmed = presentation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @ViewBuilder
    private func labeledRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)

            Text(value)
                .font(AppFont.subheadline())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsStatusPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(AppFont.caption(weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
    }
}

private struct SettingsMacNameSheet: View {
    @Binding var nickname: String
    let currentName: String
    let systemName: String

    @Environment(\.dismiss) private var dismiss
    @State private var draftNickname = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mac name")
                        .font(AppFont.subheadline(weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(currentName)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                }

                TextField(systemName, text: $draftNickname)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .font(AppFont.subheadline())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemFill))
                    )

                Text("This nickname stays on this iPhone and appears anywhere this Mac is shown.")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    SettingsButton("Use Default", role: .cancel) {
                        nickname = ""
                        dismiss()
                    }
                    .opacity(canResetToDefault ? 1 : 0.5)
                    .disabled(!canResetToDefault)

                    SettingsButton("Save") {
                        nickname = draftNickname
                        dismiss()
                    }
                    .opacity(canSave ? 1 : 0.5)
                    .disabled(!canSave)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
            .navigationTitle("Edit Mac Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                draftNickname = nickname
            }
        }
    }

    private var canSave: Bool {
        draftNickname != nickname
    }

    private var canResetToDefault: Bool {
        !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(CodexService())
    }
}
