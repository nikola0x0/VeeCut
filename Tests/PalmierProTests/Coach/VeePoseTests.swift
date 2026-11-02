import Testing
@testable import PalmierPro

struct VeePoseTests {
    @Test(arguments: [
        (CoachState.asking(overview: ""), false, false, VeeIllustration.Name.hello),
        (.planning, true, false, .vlogging),
        (.planning, false, false, .planning),
        (.hidden, false, true, .listening),
        (.asking(overview: ""), false, true, .listening),
        (.failed(.emptyPlan), false, false, .oops),
        (.hidden, false, false, .avatar),
    ])
    func posesFollowWhatVeeIsDoing(coach: CoachState, isReading: Bool, isListening: Bool, expected: VeeIllustration.Name) {
        #expect(VeePose.pose(coach: coach, isReading: isReading, isListening: isListening) == expected)
    }
}
