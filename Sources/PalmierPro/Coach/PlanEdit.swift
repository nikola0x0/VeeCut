import Foundation

enum PlanEdit: Equatable, Sendable {
    case rename(String, to: String)
    case setTarget(String, seconds: Double)
    case move(String, by: Int)
    case add(PlanSection, after: String?)
    case delete(String)
}

enum PlanEditFailure: Error, Equatable {
    case noPlan, unknownSection, invalidTitle, invalidTarget, invalidMove
}

extension EditPlan {
    static let targetRange = 1.0...600.0
    static let maximumTitleLength = 80

    static func normalizedTitle(_ raw: String) throws(PlanEditFailure) -> String {
        let title = raw.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, title.count <= maximumTitleLength,
              title.rangeOfCharacter(from: .controlCharacters.union(.newlines)) == nil else { throw .invalidTitle }
        return title
    }

    /// The plan with every edit applied in order; any invalid edit rejects the whole list.
    func applying(_ edits: [PlanEdit]) throws(PlanEditFailure) -> EditPlan {
        var plan = self
        for edit in edits {
            switch edit {
            case .rename(let id, let title):
                let index = try plan.sectionIndex(id)
                plan.sections[index].title = try Self.normalizedTitle(title)
            case .setTarget(let id, let seconds):
                let index = try plan.sectionIndex(id)
                guard seconds.isFinite, Self.targetRange.contains(seconds) else { throw .invalidTarget }
                plan.sections[index].targetSeconds = seconds
            case .move(let id, let offset):
                let index = try plan.sectionIndex(id)
                let (destination, overflow) = index.addingReportingOverflow(offset)
                guard !overflow, plan.sections.indices.contains(destination) else { throw .invalidMove }
                plan.sections.insert(plan.sections.remove(at: index), at: destination)
            case .add(var section, let after):
                guard !plan.sections.contains(where: { $0.id == section.id }) else { throw .unknownSection }
                section.title = try Self.normalizedTitle(section.title)
                guard section.targetSeconds.isFinite, Self.targetRange.contains(section.targetSeconds) else { throw .invalidTarget }
                var index = plan.sections.count
                if let after { index = try plan.sectionIndex(after) + 1 }
                plan.sections.insert(section, at: index)
            case .delete(let id):
                plan.sections.remove(at: try plan.sectionIndex(id))
            }
        }
        return plan
    }

    private func sectionIndex(_ id: String) throws(PlanEditFailure) -> Int {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { throw .unknownSection }
        return index
    }
}
