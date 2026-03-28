// FILE: CodexService+RuntimeConfig.swift
// Purpose: Runtime model/reasoning/access preferences, per-thread overrides, and model/list loading.
// Layer: Service
// Exports: CodexService runtime config APIs
// Depends on: CodexModelOption, CodexReasoningEffortOption, CodexAccessMode

import Foundation

extension CodexService {
    func mergedAvailableModels() -> [CodexModelOption] {
        func mergeKey(for model: CodexModelOption) -> String {
            let normalizedModel = model.model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalizedModel.isEmpty {
                return normalizedModel
            }
            return model.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        var mergedByKey: [String: CodexModelOption] = [:]
        var insertionOrder: [String] = []

        for model in availableModels {
            let key = mergeKey(for: model)
            guard !key.isEmpty else { continue }
            if mergedByKey[key] == nil {
                insertionOrder.append(key)
            }
            mergedByKey[key] = model
        }

        for customModel in customModelOptions {
            let key = mergeKey(for: customModel)
            guard !key.isEmpty else { continue }
            if let serverModel = mergedByKey[key] {
                mergedByKey[key] = customModel.mergedWithRuntimeFallback(serverModel)
            } else {
                insertionOrder.append(key)
                mergedByKey[key] = customModel
            }
        }

        var mergedModels = insertionOrder.compactMap { mergedByKey[$0] }
        if let placeholderModel = selectedModelPlaceholderIfNeeded(from: mergedModels) {
            mergedModels.append(placeholderModel)
        }
        return mergedModels
    }

    // Resolves the effective per-chat override record after normalizing the thread id.
    func threadRuntimeOverride(for threadId: String?) -> CodexThreadRuntimeOverride? {
        guard let normalizedThreadID = normalizedInterruptIdentifier(threadId) else {
            return nil
        }
        return threadRuntimeOverridesByThreadID[normalizedThreadID]
    }

    // Sends one request while trying approvalPolicy enum variants for cross-version compatibility.
    func sendRequestWithApprovalPolicyFallback(
        method: String,
        baseParams: RPCObject,
        context: String
    ) async throws -> RPCMessage {
        let policies = selectedAccessMode.approvalPolicyCandidates
        var lastError: Error?

        for (index, policy) in policies.enumerated() {
            var params = baseParams
            params["approvalPolicy"] = .string(policy)

            do {
                return try await sendRequest(method: method, params: .object(params))
            } catch {
                lastError = error
                let hasMorePolicies = index < (policies.count - 1)
                if hasMorePolicies, shouldRetryWithApprovalPolicyFallback(error) {
                    debugRuntimeLog("\(method) \(context) fallback approvalPolicy=\(policy)")
                    continue
                }
                throw error
            }
        }

        throw lastError ?? CodexServiceError.invalidResponse("\(method) failed with unknown approvalPolicy error")
    }

    func listModels() async throws {
        isLoadingModels = true
        defer { isLoadingModels = false }

        do {
            let response = try await sendRequest(
                method: "model/list",
                params: .object([
                    "cursor": .null,
                    "limit": .integer(50),
                    "includeHidden": .bool(false),
                ])
            )

            guard let resultObject = response.result?.objectValue else {
                throw CodexServiceError.invalidResponse("model/list response missing payload")
            }

            let items =
                resultObject["items"]?.arrayValue
                ?? resultObject["data"]?.arrayValue
                ?? resultObject["models"]?.arrayValue
                ?? []

            let decodedModels = items.compactMap { decodeModel(CodexModelOption.self, from: $0) }
            availableModels = decodedModels
            modelsErrorMessage = nil
            normalizeRuntimeSelectionsAfterModelsUpdate()

            debugRuntimeLog("model/list success count=\(decodedModels.count)")
        } catch {
            handleModelListFailure(error)
            throw error
        }
    }

    func setSelectedModelId(_ modelId: String?) {
        let normalized = modelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedModelId = (normalized?.isEmpty == false) ? normalized : nil
        normalizeRuntimeSelectionsAfterModelsUpdate()
    }

    func saveCustomModel(
        model: String,
        displayName: String,
        inheritsOpenAIDefaultReasoningEfforts: Bool,
        supportedReasoningEfforts: [CodexReasoningEffortOption],
        defaultReasoningEffort: String?
    ) {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty, !normalizedDisplayName.isEmpty else {
            return
        }

        let normalizedSupportedReasoningEfforts = supportedReasoningEfforts.filter {
            !$0.reasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let supportedReasoningEffortsSet = Set(normalizedSupportedReasoningEfforts.map(\.reasoningEffort))
        let normalizedDefaultReasoningEffort = defaultReasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDefaultReasoningEffort: String?
        if inheritsOpenAIDefaultReasoningEfforts {
            resolvedDefaultReasoningEffort = normalizedDefaultReasoningEffort
        } else if let normalizedDefaultReasoningEffort,
                  supportedReasoningEffortsSet.contains(normalizedDefaultReasoningEffort) {
            resolvedDefaultReasoningEffort = normalizedDefaultReasoningEffort
        } else {
            resolvedDefaultReasoningEffort = normalizedSupportedReasoningEfforts.first?.reasoningEffort
        }

        let customModel = CodexModelOption(
            id: normalizedModel,
            model: normalizedModel,
            displayName: normalizedDisplayName,
            description: "Custom model",
            isDefault: false,
            isCustom: true,
            supportedReasoningEfforts: normalizedSupportedReasoningEfforts,
            defaultReasoningEffort: resolvedDefaultReasoningEffort,
            inheritsOpenAIDefaultReasoningEfforts: inheritsOpenAIDefaultReasoningEfforts
        )
        let normalizedKey = normalizedModel.lowercased()

        if let existingIndex = customModelOptions.firstIndex(where: {
            $0.id.lowercased() == normalizedKey || $0.model.lowercased() == normalizedKey
        }) {
            customModelOptions[existingIndex] = customModel
        } else {
            customModelOptions.append(customModel)
        }

        persistCustomModelOptions()
        normalizeRuntimeSelectionsAfterModelsUpdate()
    }

    func removeCustomModel(id: String) {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedID.isEmpty else {
            return
        }

        customModelOptions.removeAll {
            $0.id.lowercased() == normalizedID || $0.model.lowercased() == normalizedID
        }
        persistCustomModelOptions()
        normalizeRuntimeSelectionsAfterModelsUpdate()
    }

    func setSelectedReasoningEffort(_ effort: String?) {
        let normalized = effort?.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedReasoningEffort = (normalized?.isEmpty == false) ? normalized : nil
        normalizeRuntimeSelectionsAfterModelsUpdate()
    }

    func setThreadModelOverride(_ modelIdentifier: String?, for threadId: String?) {
        guard let normalizedThreadID = normalizedInterruptIdentifier(threadId) else {
            return
        }

        let normalizedModelIdentifier = trimmedModelIdentifier(modelIdentifier)
        mutateThreadRuntimeOverride(for: normalizedThreadID) { override in
            override.modelIdentifier = normalizedModelIdentifier
            override.overridesModel = normalizedModelIdentifier != nil
        }
    }

    func setThreadReasoningEffortOverride(_ effort: String, for threadId: String?) {
        guard let normalizedThreadID = normalizedInterruptIdentifier(threadId) else {
            return
        }

        let normalizedEffort = effort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEffort.isEmpty else {
            clearThreadReasoningEffortOverride(for: normalizedThreadID)
            return
        }

        mutateThreadRuntimeOverride(for: normalizedThreadID) { override in
            override.reasoningEffort = normalizedEffort
            override.overridesReasoning = true
        }
    }

    func clearThreadReasoningEffortOverride(for threadId: String?) {
        guard let normalizedThreadID = normalizedInterruptIdentifier(threadId) else {
            return
        }

        mutateThreadRuntimeOverride(for: normalizedThreadID) { override in
            override.reasoningEffort = nil
            override.overridesReasoning = false
        }
    }

    func setSelectedServiceTier(_ serviceTier: CodexServiceTier?) {
        selectedServiceTier = serviceTier
        persistRuntimeSelections()
    }

    func setThreadServiceTierOverride(_ serviceTier: CodexServiceTier?, for threadId: String?) {
        guard let normalizedThreadID = normalizedInterruptIdentifier(threadId) else {
            return
        }

        mutateThreadRuntimeOverride(for: normalizedThreadID) { override in
            override.serviceTierRawValue = serviceTier?.rawValue
            override.overridesServiceTier = true
        }
    }

    func clearThreadServiceTierOverride(for threadId: String?) {
        guard let normalizedThreadID = normalizedInterruptIdentifier(threadId) else {
            return
        }

        mutateThreadRuntimeOverride(for: normalizedThreadID) { override in
            override.serviceTierRawValue = nil
            override.overridesServiceTier = false
        }
    }

    func applyThreadRuntimeOverride(_ runtimeOverride: CodexThreadRuntimeOverride?, to threadId: String?) {
        guard let normalizedThreadID = normalizedInterruptIdentifier(threadId) else {
            return
        }

        guard let runtimeOverride, !runtimeOverride.isEmpty else {
            threadRuntimeOverridesByThreadID.removeValue(forKey: normalizedThreadID)
            persistThreadRuntimeOverrides()
            return
        }

        threadRuntimeOverridesByThreadID[normalizedThreadID] = runtimeOverride
        persistThreadRuntimeOverrides()
    }

    func setSelectedAccessMode(_ accessMode: CodexAccessMode) {
        selectedAccessMode = accessMode
        persistRuntimeSelections()
    }

    func selectedModelOption(threadId: String? = nil) -> CodexModelOption? {
        selectedModelOption(from: mergedAvailableModels(), threadId: threadId)
    }

    func supportedReasoningEffortsForSelectedModel(threadId: String? = nil) -> [CodexReasoningEffortOption] {
        selectedModelOption(threadId: threadId)?.resolvedSupportedReasoningEfforts() ?? []
    }

    func isThreadReasoningEffortOverridden(_ threadId: String?) -> Bool {
        guard let threadOverride = threadRuntimeOverride(for: threadId),
              threadOverride.overridesReasoning,
              let selectedReasoning = threadOverride.reasoningEffort else {
            return false
        }

        let supportedReasoningEfforts = Set(
            supportedReasoningEffortsForSelectedModel(threadId: threadId).map(\.reasoningEffort)
        )
        return supportedReasoningEfforts.contains(selectedReasoning)
    }

    func isThreadServiceTierOverridden(_ threadId: String?) -> Bool {
        threadRuntimeOverride(for: threadId)?.overridesServiceTier == true
    }

    func selectedReasoningEffortForSelectedModel(threadId: String? = nil) -> String? {
        guard let model = selectedModelOption(threadId: threadId) else {
            return nil
        }

        let resolvedSupportedReasoningEfforts = model.resolvedSupportedReasoningEfforts()
        let supported = Set(resolvedSupportedReasoningEfforts.map { $0.reasoningEffort })
        guard !supported.isEmpty else {
            return nil
        }

        if let threadOverride = threadRuntimeOverride(for: threadId),
           threadOverride.overridesReasoning,
           let selected = threadOverride.reasoningEffort,
           supported.contains(selected) {
            return selected
        }

        if let selected = selectedReasoningEffort,
           supported.contains(selected) {
            return selected
        }

        if let defaultEffort = model.resolvedDefaultReasoningEffort(),
           supported.contains(defaultEffort) {
            return defaultEffort
        }

        if supported.contains(CodexModelOption.inheritedDefaultReasoningEffort) {
            return CodexModelOption.inheritedDefaultReasoningEffort
        }

        return resolvedSupportedReasoningEfforts.first?.reasoningEffort
    }

    func runtimeModelIdentifierForTurn(threadId: String? = nil) -> String? {
        if let threadOverride = threadRuntimeOverride(for: threadId),
           threadOverride.overridesModel,
           let modelIdentifier = trimmedModelIdentifier(threadOverride.modelIdentifier) {
            return modelIdentifier
        }

        if let threadModelIdentifier = threadModelIdentifier(for: threadId) {
            return threadModelIdentifier
        }

        if let selectedModelIdentifier = selectedModelOption()?.model,
           !selectedModelIdentifier.isEmpty {
            return selectedModelIdentifier
        }

        return selectedModelIdentifier()
    }

    func effectiveServiceTier(for threadId: String? = nil) -> CodexServiceTier? {
        if let threadOverride = threadRuntimeOverride(for: threadId),
           threadOverride.overridesServiceTier {
            return threadOverride.serviceTier
        }

        return selectedServiceTier
    }

    func runtimeServiceTierForTurn(threadId: String? = nil) -> String? {
        guard supportsServiceTier else {
            return nil
        }
        return effectiveServiceTier(for: threadId)?.rawValue
    }

    func inheritRuntimeSelections(
        from sourceThreadId: String?,
        fallbackModelIdentifier: String? = nil,
        fallbackRuntimeOverride: CodexThreadRuntimeOverride? = nil
    ) {
        let sourceOverride = fallbackRuntimeOverride ?? threadRuntimeOverride(for: sourceThreadId)
        let sourceModelIdentifier = trimmedModelIdentifier(sourceOverride?.modelIdentifier)
            ?? threadModelIdentifier(for: sourceThreadId)
            ?? fallbackModelIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sourceModelIdentifier,
           !sourceModelIdentifier.isEmpty {
            selectedModelId = sourceModelIdentifier
        }

        if let sourceOverride,
           sourceOverride.overridesReasoning,
           let reasoningEffort = sourceOverride.reasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reasoningEffort.isEmpty {
            selectedReasoningEffort = reasoningEffort
        }
        if let sourceOverride,
           sourceOverride.overridesServiceTier {
            selectedServiceTier = sourceOverride.serviceTier
        }

        normalizeRuntimeSelectionsAfterModelsUpdate()
    }

    // Copies per-chat runtime overrides forward when we continue an archived thread.
    func inheritThreadRuntimeOverrides(from sourceThreadId: String?, to destinationThreadId: String?) {
        guard let normalizedSourceThreadID = normalizedInterruptIdentifier(sourceThreadId),
              let normalizedDestinationThreadID = normalizedInterruptIdentifier(destinationThreadId),
              normalizedSourceThreadID != normalizedDestinationThreadID else {
            return
        }

        guard let sourceOverride = threadRuntimeOverridesByThreadID[normalizedSourceThreadID] else {
            applyThreadRuntimeOverride(nil, to: normalizedDestinationThreadID)
            return
        }

        applyThreadRuntimeOverride(sourceOverride, to: normalizedDestinationThreadID)
    }

    func runtimeSandboxPolicyObject(for accessMode: CodexAccessMode) -> JSONValue {
        switch accessMode {
        case .onRequest:
            return .object([
                "type": .string("workspaceWrite"),
                "networkAccess": .bool(true),
            ])
        case .fullAccess:
            return .object([
                "type": .string("dangerFullAccess"),
            ])
        }
    }

    func shouldFallbackFromSandboxPolicy(_ error: Error) -> Bool {
        guard let serviceError = error as? CodexServiceError,
              case .rpcError(let rpcError) = serviceError else {
            return false
        }

        if rpcError.code != -32602 && rpcError.code != -32600 {
            return false
        }

        let loweredMessage = rpcError.message.lowercased()
        if loweredMessage.contains("thread not found") || loweredMessage.contains("unknown thread") {
            return false
        }

        return loweredMessage.contains("invalid params")
            || loweredMessage.contains("invalid param")
            || loweredMessage.contains("unknown field")
            || loweredMessage.contains("unexpected field")
            || loweredMessage.contains("unrecognized field")
            || loweredMessage.contains("failed to parse")
            || loweredMessage.contains("unsupported")
    }

    func sendRequestWithSandboxFallback(method: String, baseParams: RPCObject) async throws -> RPCMessage {
        var firstAttemptParams = baseParams
        firstAttemptParams["sandboxPolicy"] = runtimeSandboxPolicyObject(for: selectedAccessMode)

        do {
            debugRuntimeLog("\(method) using sandboxPolicy")
            return try await sendRequestWithApprovalPolicyFallback(
                method: method,
                baseParams: firstAttemptParams,
                context: "sandboxPolicy"
            )
        } catch {
            guard shouldFallbackFromSandboxPolicy(error) else {
                throw error
            }
        }

        var secondAttemptParams = baseParams
        secondAttemptParams["sandbox"] = .string(selectedAccessMode.sandboxLegacyValue)

        do {
            debugRuntimeLog("\(method) fallback using sandbox")
            return try await sendRequestWithApprovalPolicyFallback(
                method: method,
                baseParams: secondAttemptParams,
                context: "sandbox"
            )
        } catch {
            guard shouldFallbackFromSandboxPolicy(error) else {
                throw error
            }
        }

        var finalAttemptParams = baseParams
        debugRuntimeLog("\(method) fallback using minimal payload")
        return try await sendRequestWithApprovalPolicyFallback(
            method: method,
            baseParams: finalAttemptParams,
            context: "minimal"
        )
    }

    func handleModelListFailure(_ error: Error) {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = message.isEmpty ? "Unable to load models" : message
        modelsErrorMessage = normalized
        debugRuntimeLog("model/list failed: \(normalized)")
    }

    func debugRuntimeLog(_ message: String) {
#if DEBUG
        print("[CodexRuntime] \(message)")
#endif
    }

    func shouldRetryWithApprovalPolicyFallback(_ error: Error) -> Bool {
        guard let serviceError = error as? CodexServiceError,
              case .rpcError(let rpcError) = serviceError else {
            return false
        }

        if rpcError.code != -32600 && rpcError.code != -32602 {
            return false
        }

        let message = rpcError.message.lowercased()
        return message.contains("approval")
            || message.contains("unknown variant")
            || message.contains("expected one of")
            || message.contains("onrequest")
            || message.contains("on-request")
    }
}

private extension CodexService {
    // Centralizes thread-override mutation so empty records never linger in storage.
    func mutateThreadRuntimeOverride(
        for threadId: String,
        mutate: (inout CodexThreadRuntimeOverride) -> Void
    ) {
        var currentOverride = threadRuntimeOverridesByThreadID[threadId] ?? CodexThreadRuntimeOverride(
            modelIdentifier: nil,
            reasoningEffort: nil,
            serviceTierRawValue: nil,
            overridesModel: false,
            overridesReasoning: false,
            overridesServiceTier: false
        )

        mutate(&currentOverride)

        if currentOverride.isEmpty {
            threadRuntimeOverridesByThreadID.removeValue(forKey: threadId)
        } else {
            threadRuntimeOverridesByThreadID[threadId] = currentOverride
        }

        persistThreadRuntimeOverrides()
    }

    func normalizeRuntimeSelectionsAfterModelsUpdate() {
        let mergedModels = mergedAvailableModels()
        let resolvedModel = selectedModelOption(from: mergedModels) ?? fallbackModel(from: mergedModels)
        selectedModelId = resolvedModel?.id

        if let resolvedModel {
            let resolvedSupportedReasoningEfforts = resolvedModel.resolvedSupportedReasoningEfforts()
            let supported = Set(resolvedSupportedReasoningEfforts.map { $0.reasoningEffort })
            if supported.isEmpty {
                selectedReasoningEffort = nil
            } else if let selectedReasoningEffort,
                      supported.contains(selectedReasoningEffort) {
                // Keep current reasoning.
            } else if let modelDefault = resolvedModel.resolvedDefaultReasoningEffort(),
                      supported.contains(modelDefault) {
                selectedReasoningEffort = modelDefault
            } else if supported.contains(CodexModelOption.inheritedDefaultReasoningEffort) {
                selectedReasoningEffort = CodexModelOption.inheritedDefaultReasoningEffort
            } else {
                selectedReasoningEffort = resolvedSupportedReasoningEfforts.first?.reasoningEffort
            }
        } else {
            selectedReasoningEffort = nil
        }

        persistRuntimeSelections()
    }

    func selectedModelOption(from models: [CodexModelOption], threadId: String? = nil) -> CodexModelOption? {
        let resolvedModelIdentifier = runtimeModelIdentifierForTurn(threadId: threadId)
            ?? selectedModelIdentifier()
        let resolvedModelLookupKey = normalizedModelLookupKey(resolvedModelIdentifier)

        if let resolvedModelLookupKey,
           let directMatch = models.first(where: {
               normalizedModelLookupKey($0.id) == resolvedModelLookupKey
                   || normalizedModelLookupKey($0.model) == resolvedModelLookupKey
           }) {
            return directMatch
        }

        if let resolvedModelIdentifier {
            let placeholderReasoningEffort: String?
            if let threadOverride = threadRuntimeOverride(for: threadId),
               threadOverride.overridesReasoning {
                placeholderReasoningEffort = threadOverride.reasoningEffort
            } else {
                placeholderReasoningEffort = selectedReasoningEffort
            }

            return CodexModelOption.placeholderModel(
                identifier: resolvedModelIdentifier,
                selectedReasoningEffort: placeholderReasoningEffort
            )
        }

        return nil
    }

    func fallbackModel(from models: [CodexModelOption]) -> CodexModelOption? {
        if let defaultModel = models.first(where: { $0.isDefault }) {
            return defaultModel
        }
        return models.first
    }

    func selectedModelIdentifier() -> String? {
        trimmedModelIdentifier(selectedModelId)
    }

    func threadModelIdentifier(for threadId: String?) -> String? {
        guard let normalizedThreadID = normalizedInterruptIdentifier(threadId) else {
            return nil
        }
        return trimmedModelIdentifier(thread(for: normalizedThreadID)?.model)
    }

    func selectedModelPlaceholderIfNeeded(from models: [CodexModelOption]) -> CodexModelOption? {
        guard let selectedModelLookupKey = normalizedModelLookupKey(selectedModelId),
              let selectedModelIdentifier = selectedModelIdentifier() else {
            return nil
        }

        guard !models.contains(where: {
            normalizedModelLookupKey($0.id) == selectedModelLookupKey
                || normalizedModelLookupKey($0.model) == selectedModelLookupKey
        }) else {
            return nil
        }

        return CodexModelOption.placeholderModel(
            identifier: selectedModelIdentifier,
            selectedReasoningEffort: selectedReasoningEffort
        )
    }

    func trimmedModelIdentifier(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    func normalizedModelLookupKey(_ value: String?) -> String? {
        trimmedModelIdentifier(value)?.lowercased()
    }

    func persistRuntimeSelections() {
        if let selectedModelId, !selectedModelId.isEmpty {
            defaults.set(selectedModelId, forKey: Self.selectedModelIdDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.selectedModelIdDefaultsKey)
        }

        if let selectedReasoningEffort, !selectedReasoningEffort.isEmpty {
            defaults.set(selectedReasoningEffort, forKey: Self.selectedReasoningEffortDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.selectedReasoningEffortDefaultsKey)
        }

        if let selectedServiceTier {
            defaults.set(selectedServiceTier.rawValue, forKey: Self.selectedServiceTierDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.selectedServiceTierDefaultsKey)
        }

        defaults.set(selectedAccessMode.rawValue, forKey: Self.selectedAccessModeDefaultsKey)
        persistCustomModelOptions()
        persistThreadRuntimeOverrides()
    }

    func persistCustomModelOptions() {
        guard !customModelOptions.isEmpty,
              let encodedCustomModels = try? encoder.encode(customModelOptions) else {
            defaults.removeObject(forKey: Self.customModelOptionsDefaultsKey)
            return
        }

        defaults.set(encodedCustomModels, forKey: Self.customModelOptionsDefaultsKey)
    }

    func persistThreadRuntimeOverrides() {
        guard !threadRuntimeOverridesByThreadID.isEmpty,
              let encodedOverrides = try? encoder.encode(threadRuntimeOverridesByThreadID) else {
            defaults.removeObject(forKey: Self.threadRuntimeOverridesDefaultsKey)
            return
        }

        defaults.set(encodedOverrides, forKey: Self.threadRuntimeOverridesDefaultsKey)
    }
}
