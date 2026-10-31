import Foundation
import Testing
@testable import PalmierPro

struct MetaResponseStreamTests {
    @Test func thinkingAndTextDeltasAreSeparated() {
        let thinking = #"data: {"delta":"Allocating footage durations to fit a 30-second reel.","output_index":0,"sequence_number":4,"summary_index":0,"type":"response.reasoning_summary_text.delta"}"#
        let text = #"data: {"content_index":0,"delta":"{\"sections\": [{\"","output_index":1,"sequence_number":10,"type":"response.output_text.delta"}"#

        #expect(MetaResponseStream.event(fromLine: thinking) == .thinking("Allocating footage durations to fit a 30-second reel."))
        #expect(MetaResponseStream.event(fromLine: text) == .text(#"{"sections": [{""#))
        #expect(MetaResponseStream.event(fromLine: "event: response.output_text.delta") == nil)
    }

    @Test func aFailedResponseCarriesItsMessage() {
        let failed = #"data: {"type":"response.failed","response":{"error":{"message":"overloaded"}}}"#
        #expect(MetaResponseStream.event(fromLine: failed) == .failed("overloaded"))
    }
}
