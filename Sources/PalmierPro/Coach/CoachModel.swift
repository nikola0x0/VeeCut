import Foundation

/// The structured Muse Spark call the coach makes; tests inject a recorder.
protocol CoachModel: Sendable {
    func structuredResponse(model: String, instructions: String, parts: [MetaInputPart], schemaName: String, schemaJSON: Data) async throws -> String
    func structuredResponse(model: String, instructions: String, parts: [MetaInputPart], schemaName: String, schemaJSON: Data,
                            onThinking: @escaping @Sendable (String) async -> Void) async throws -> String
}

extension CoachModel {
    /// Models that can't stream their thinking answer the same call without it.
    func structuredResponse(model: String, instructions: String, parts: [MetaInputPart], schemaName: String, schemaJSON: Data,
                            onThinking: @escaping @Sendable (String) async -> Void) async throws -> String {
        try await structuredResponse(model: model, instructions: instructions, parts: parts, schemaName: schemaName, schemaJSON: schemaJSON)
    }
}

extension MetaModelClient: CoachModel {}

enum CoachFailure: Error, Equatable {
    case missingAPIKey, noFootage, emptyPlan, cancelled, service(String)
}
