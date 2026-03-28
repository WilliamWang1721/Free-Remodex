// FILE: CodexModelOption.swift
// Purpose: Represents one model entry returned by model/list.
// Layer: Model
// Exports: CodexModelOption
// Depends on: Foundation, CodexReasoningEffortOption

import Foundation

struct CodexModelOption: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let model: String
    let displayName: String
    let description: String
    let isDefault: Bool
    let isCustom: Bool
    let supportedReasoningEfforts: [CodexReasoningEffortOption]
    let defaultReasoningEffort: String?
    let inheritsOpenAIDefaultReasoningEfforts: Bool

    static let inheritedDefaultReasoningEffort = "medium"

    static let inheritedReasoningEffortOptions: [CodexReasoningEffortOption] = [
        CodexReasoningEffortOption(reasoningEffort: "minimal", displayName: "Low"),
        CodexReasoningEffortOption(reasoningEffort: "medium", displayName: "Medium"),
        CodexReasoningEffortOption(reasoningEffort: "high", displayName: "High"),
        CodexReasoningEffortOption(reasoningEffort: "extra_high", displayName: "Extra High"),
    ]

    init(
        id: String,
        model: String,
        displayName: String,
        description: String,
        isDefault: Bool,
        isCustom: Bool = false,
        supportedReasoningEfforts: [CodexReasoningEffortOption],
        defaultReasoningEffort: String?,
        inheritsOpenAIDefaultReasoningEfforts: Bool = false
    ) {
        self.id = id
        self.model = model
        self.displayName = displayName
        self.description = description
        self.isDefault = isDefault
        self.isCustom = isCustom
        self.supportedReasoningEfforts = Self.normalizedReasoningEfforts(supportedReasoningEfforts)

        let normalizedDefault = defaultReasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.defaultReasoningEffort = (normalizedDefault?.isEmpty == false) ? normalizedDefault : nil
        self.inheritsOpenAIDefaultReasoningEfforts = inheritsOpenAIDefaultReasoningEfforts
    }

    var hasExplicitReasoningConfiguration: Bool {
        inheritsOpenAIDefaultReasoningEfforts || !supportedReasoningEfforts.isEmpty || defaultReasoningEffort != nil
    }

    func resolvedSupportedReasoningEfforts(fallback: CodexModelOption? = nil) -> [CodexReasoningEffortOption] {
        if inheritsOpenAIDefaultReasoningEfforts {
            return Self.inheritedReasoningEffortOptions
        }
        if !supportedReasoningEfforts.isEmpty {
            return supportedReasoningEfforts
        }
        return fallback?.supportedReasoningEfforts ?? []
    }

    func resolvedDefaultReasoningEffort(fallback: CodexModelOption? = nil) -> String? {
        let resolvedSupportedEfforts = resolvedSupportedReasoningEfforts(fallback: fallback)
        let supportedValues = Set(resolvedSupportedEfforts.map(\.reasoningEffort))

        if let defaultReasoningEffort,
           supportedValues.contains(defaultReasoningEffort) {
            return defaultReasoningEffort
        }

        if inheritsOpenAIDefaultReasoningEfforts,
           supportedValues.contains(Self.inheritedDefaultReasoningEffort) {
            return Self.inheritedDefaultReasoningEffort
        }

        if !supportedReasoningEfforts.isEmpty {
            return supportedReasoningEfforts.first?.reasoningEffort
        }

        if let fallback,
           let fallbackDefault = fallback.defaultReasoningEffort,
           supportedValues.contains(fallbackDefault) {
            return fallbackDefault
        }

        return resolvedSupportedEfforts.first?.reasoningEffort
    }

    func mergedWithRuntimeFallback(_ runtimeModel: CodexModelOption) -> CodexModelOption {
        CodexModelOption(
            id: id,
            model: model,
            displayName: displayName,
            description: description.isEmpty ? runtimeModel.description : description,
            isDefault: runtimeModel.isDefault,
            isCustom: true,
            supportedReasoningEfforts: hasExplicitReasoningConfiguration
                ? resolvedSupportedReasoningEfforts()
                : runtimeModel.supportedReasoningEfforts,
            defaultReasoningEffort: hasExplicitReasoningConfiguration
                ? resolvedDefaultReasoningEffort()
                : runtimeModel.defaultReasoningEffort,
            inheritsOpenAIDefaultReasoningEfforts: inheritsOpenAIDefaultReasoningEfforts
        )
    }

    static func placeholderModel(
        identifier: String,
        selectedReasoningEffort: String? = nil
    ) -> CodexModelOption {
        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelectedReasoning = selectedReasoningEffort?.trimmingCharacters(in: .whitespacesAndNewlines)

        var efforts = inheritedReasoningEffortOptions
        if let normalizedSelectedReasoning,
           !normalizedSelectedReasoning.isEmpty,
           !efforts.contains(where: { $0.reasoningEffort == normalizedSelectedReasoning }) {
            efforts.append(
                CodexReasoningEffortOption(
                    reasoningEffort: normalizedSelectedReasoning,
                    displayName: nil
                )
            )
        }

        return CodexModelOption(
            id: normalizedIdentifier,
            model: normalizedIdentifier,
            displayName: normalizedIdentifier,
            description: "Missing from current runtime list",
            isDefault: false,
            isCustom: true,
            supportedReasoningEfforts: efforts,
            defaultReasoningEffort: normalizedSelectedReasoning,
            inheritsOpenAIDefaultReasoningEfforts: true
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case displayName
        case displayNameSnake = "display_name"
        case description
        case isDefault
        case isDefaultSnake = "is_default"
        case isCustom
        case isCustomSnake = "is_custom"
        case supportedReasoningEfforts
        case supportedReasoningEffortsSnake = "supported_reasoning_efforts"
        case defaultReasoningEffort
        case defaultReasoningEffortSnake = "default_reasoning_effort"
        case inheritsOpenAIDefaultReasoningEfforts
        case inheritsOpenAIDefaultReasoningEffortsSnake = "inherits_openai_default_reasoning_efforts"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let modelValue = try container.decodeIfPresent(String.self, forKey: .model)
        let idValue = try container.decodeIfPresent(String.self, forKey: .id)
        let rawModel = modelValue ?? idValue ?? ""
        let normalizedModel = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)

        let rawID = idValue ?? normalizedModel
        let normalizedID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)

        let displayNameValue = try container.decodeIfPresent(String.self, forKey: .displayName)
        let displayNameSnakeValue = try container.decodeIfPresent(String.self, forKey: .displayNameSnake)
        let rawDisplayName = displayNameValue ?? displayNameSnakeValue ?? normalizedModel
        let normalizedDisplayName = rawDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawDescription = (try container.decodeIfPresent(String.self, forKey: .description)) ?? ""

        let camelEfforts = try container.decodeIfPresent(
            [CodexReasoningEffortOption].self,
            forKey: .supportedReasoningEfforts
        )
        let snakeEfforts = try container.decodeIfPresent(
            [CodexReasoningEffortOption].self,
            forKey: .supportedReasoningEffortsSnake
        )
        let normalizedEfforts = Self.normalizedReasoningEfforts(camelEfforts ?? snakeEfforts ?? [])

        let camelDefaultEffort = try container.decodeIfPresent(String.self, forKey: .defaultReasoningEffort)
        let snakeDefaultEffort = try container.decodeIfPresent(String.self, forKey: .defaultReasoningEffortSnake)
        let defaultEffort = camelDefaultEffort ?? snakeDefaultEffort

        let camelDefaultFlag = try container.decodeIfPresent(Bool.self, forKey: .isDefault)
        let snakeDefaultFlag = try container.decodeIfPresent(Bool.self, forKey: .isDefaultSnake)
        let camelCustomFlag = try container.decodeIfPresent(Bool.self, forKey: .isCustom)
        let snakeCustomFlag = try container.decodeIfPresent(Bool.self, forKey: .isCustomSnake)
        let camelInheritedFlag = try container.decodeIfPresent(
            Bool.self,
            forKey: .inheritsOpenAIDefaultReasoningEfforts
        )
        let snakeInheritedFlag = try container.decodeIfPresent(
            Bool.self,
            forKey: .inheritsOpenAIDefaultReasoningEffortsSnake
        )

        id = normalizedID.isEmpty ? normalizedModel : normalizedID
        model = normalizedModel
        displayName = normalizedDisplayName.isEmpty ? normalizedModel : normalizedDisplayName
        description = rawDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        isDefault = camelDefaultFlag ?? snakeDefaultFlag ?? false
        isCustom = camelCustomFlag ?? snakeCustomFlag ?? false
        supportedReasoningEfforts = normalizedEfforts

        let normalizedDefault = defaultEffort?.trimmingCharacters(in: .whitespacesAndNewlines)
        defaultReasoningEffort = (normalizedDefault?.isEmpty == false) ? normalizedDefault : nil
        inheritsOpenAIDefaultReasoningEfforts = camelInheritedFlag ?? snakeInheritedFlag ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(model, forKey: .model)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(description, forKey: .description)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(isCustom, forKey: .isCustom)
        try container.encode(supportedReasoningEfforts, forKey: .supportedReasoningEfforts)
        try container.encodeIfPresent(defaultReasoningEffort, forKey: .defaultReasoningEffort)
        try container.encode(
            inheritsOpenAIDefaultReasoningEfforts,
            forKey: .inheritsOpenAIDefaultReasoningEfforts
        )
    }

    private static func normalizedReasoningEfforts(
        _ efforts: [CodexReasoningEffortOption]
    ) -> [CodexReasoningEffortOption] {
        var seenEfforts: Set<String> = []
        var normalizedEfforts: [CodexReasoningEffortOption] = []

        for effort in efforts {
            let normalizedReasoningEffort = effort.reasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedReasoningEffort.isEmpty,
                  !seenEfforts.contains(normalizedReasoningEffort) else {
                continue
            }

            seenEfforts.insert(normalizedReasoningEffort)
            normalizedEfforts.append(
                CodexReasoningEffortOption(
                    reasoningEffort: normalizedReasoningEffort,
                    displayName: effort.displayName,
                    description: effort.description
                )
            )
        }

        return normalizedEfforts
    }
}
