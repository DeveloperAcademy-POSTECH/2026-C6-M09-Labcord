import Foundation
import LabcordShared

enum WatchPresentationRules {
    static func accepts(revision: UInt64, previous: UInt64?) -> Bool {
        previous.map { revision > $0 } ?? true
    }

    struct ProtocolTimerChoice: Equatable, Identifiable {
        let seconds: Int
        let occurrence: Int
        var id: String { "\(seconds):\(occurrence)" }
    }

    static func protocolTimerChoices(_ durations: [Int]) -> [ProtocolTimerChoice] {
        var occurrences: [Int: Int] = [:]
        return durations.map { seconds in
            let occurrence = occurrences[seconds, default: 0]
            occurrences[seconds] = occurrence + 1
            return ProtocolTimerChoice(seconds: seconds, occurrence: occurrence)
        }
    }

    static func formatDuration(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
    }

    static func recordingDuration(_ recording: WatchScreenRecording, at date: Date) -> Int? {
        let elapsed: TimeInterval?
        if recording.phase == .capturing || recording.phase == .recording {
            elapsed = recording.startedAt.map { max(0, date.timeIntervalSince($0)) }
        } else {
            elapsed = recording.elapsedSeconds
        }
        guard let elapsed, elapsed.isFinite, elapsed >= 0, elapsed < Double(Int.max) else {
            return nil
        }
        return Int(elapsed)
    }
}
