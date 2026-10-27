import Foundation
import Testing
@testable import PalmierPro

/// End-to-end against Muse Spark with the real look instructions, schema, and parser.
/// Opt in with VEECUT_LIVE_MUSE=1 and MODEL_API_KEY.
@Suite("Live — Muse Spark described look", .enabled(if: ProcessInfo.processInfo.environment["VEECUT_LIVE_MUSE"] == "1"))
@MainActor
struct LiveDescribedLookTests {
    @Test(arguments: [
        ("warm golden hour vlog, subject pops", true),
        ("cold moody thriller, crushed background", true),
        ("teal and orange blockbuster", false),
    ])
    func buildsAnApplicableLook(_ description: String, hasSubject: Bool) async throws {
        let client = MetaModelClient(apiKey: ProcessInfo.processInfo.environment["MODEL_API_KEY"] ?? "")
        let text = try await client.structuredResponse(
            model: DescribedLook.model, instructions: DescribedLook.instructions(hasSubject: hasSubject), prompt: description,
            schemaName: "look", schemaJSON: try JSONSerialization.data(withJSONObject: DescribedLook.schema(hasSubject: hasSubject))
        )
        let look = try DescribedLook.parse(text, hasSubject: hasSubject)
        print("LOOK \(look.name): subject=\(look.plan.subject.map(\.type)) background=\(look.plan.background.map(\.type)) frame=\(look.plan.frame.map(\.type)) skipped=\(look.skipped)")
        #expect(!look.plan.isEmpty)
        #expect(look.skipped.isEmpty)
    }
}
