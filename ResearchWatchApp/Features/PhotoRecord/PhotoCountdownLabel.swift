import LabcordShared
import SwiftUI

struct WatchPhotoCountdown {
    let endsAt: Date

    init?(screen: WatchScreenSnapshot?, experimentID: UUID, recordID: UUID? = nil) {
        guard let screen, screen.recordingExperimentID == experimentID,
              let recording = screen.recording, recording.experimentID == experimentID,
              recording.kind == .photo, recording.phase == .capturing,
              let end = recording.countdownEndsAt else { return nil }
        if let recordID {
            guard recording.id == recordID else { return nil }
        } else {
            guard recording.origin == .phone else { return nil }
        }
        endsAt = end
    }

    func updates(from start: Date) -> some Sequence<Date> {
        sequence(first: start) { date in
            guard let seconds = remainingSeconds(at: date) else { return nil }
            return endsAt.addingTimeInterval(1 - Double(seconds))
        }
    }

    func remainingSeconds(at date: Date) -> Int? {
        let remaining = ceil(endsAt.timeIntervalSince(date))
        guard remaining > 0, remaining < Double(Int.max) else { return nil }
        return Int(remaining)
    }
}

struct PhotoCountdownLabel: View {
    let countdown: WatchPhotoCountdown?
    let fallback: LocalizedStringKey

    var body: some View {
        if let countdown {
            TimelineView(.explicit(countdown.updates(from: .now))) { timeline in
                if let seconds = countdown.remainingSeconds(at: timeline.date) {
                    Text("촬영까지 \(seconds)초")
                        .monospacedDigit()
                        .accessibilityIdentifier("watch.photo.countdown")
                } else {
                    Text(fallback)
                }
            }
        } else {
            Text(fallback)
        }
    }
}
