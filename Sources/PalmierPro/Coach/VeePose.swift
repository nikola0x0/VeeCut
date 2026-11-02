/// Which drawing of Vee matches what Vee is doing.
enum VeePose {
    static func pose(coach: CoachState, isReading: Bool, isListening: Bool) -> VeeIllustration.Name {
        if isListening { return .listening }
        switch coach {
        case .asking: return .hello
        case .planning: return isReading ? .vlogging : .planning
        case .failed: return .oops
        case .hidden: return .avatar
        }
    }
}
