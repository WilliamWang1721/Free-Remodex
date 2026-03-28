// FILE: CodexReasoningEffortOption.swift
// Purpose: Represents one reasoning effort option for a runtime model.
// Layer: Model
// Exports: CodexReasoningEffortOption
// Depends on: Foundation

import Foundation

struct CodexReasoningEffortOption: Identifiable, Codable, Hashable, Sendable {
    let reasoningEffort: String
    let displayName: String?
    let description: String

    var id: String { reasoningEffort }

    init(
        reasoningEffort: String,
        displayName: String? = nil,
        description: String = ""
    ) {
        self.reasoningEffort = reasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = (normalizedDisplayName?.isEmpty == false) ? normalizedDisplayName : nil
        self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum CodingKeys: String, CodingKey {
        case reasoningEffort
        case reasoningEffortSnake = "reasoning_effort"
        case displayName
        case displayNameSnake = "display_name"
        case description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let camelEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
        let snakeEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffortSnake)
        let effort = camelEffort ?? snakeEffort ?? ""

        let camelDisplayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        let snakeDisplayName = try container.decodeIfPresent(String.self, forKey: .displayNameSnake)
        let normalizedDisplayName = (camelDisplayName ?? snakeDisplayName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        reasoningEffort = effort.trimmingCharacters(in: .whitespacesAndNewlines)
        displayName = (normalizedDisplayName?.isEmpty == false) ? normalizedDisplayName : nil
        description = (try container.decodeIfPresent(String.self, forKey: .description) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reasoningEffort, forKey: .reasoningEffort)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(description, forKey: .description)
    }
}
