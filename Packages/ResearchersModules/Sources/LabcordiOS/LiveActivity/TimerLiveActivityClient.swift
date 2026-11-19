import ActivityKit
import ComposableArchitecture
import Foundation
import LabcordShared

public struct TimerLiveActivityClient: Sendable {
    private let applyTimers: @MainActor @Sendable (
        UUID, String, [TimerActivityAttributes.ContentState]
    ) async -> Void
    public var dismissCompleted: @MainActor @Sendable (UUID) async -> Void

    @MainActor private static var pendingSynchronizations:
        [UUID: (id: UUID, task: Task<Void, Never>)] = [:]

    public init(
        synchronize: @escaping @MainActor @Sendable (
            UUID, String, [TimerActivityAttributes.ContentState]
        ) async -> Void,
        dismissCompleted: @escaping @MainActor @Sendable (UUID) async -> Void
    ) {
        self.applyTimers = synchronize
        self.dismissCompleted = dismissCompleted
    }

    @MainActor
    public func scheduleSynchronization(
        _ experimentID: UUID, _ title: String, _ timers: [TimerActivityAttributes.ContentState]
    ) -> Task<Void, Never> {
        let previous = Self.pendingSynchronizations[experimentID]?.task
        let id = UUID()
        let task = Task {
            await previous?.value
            await applyTimers(experimentID, title, timers)
            if Self.pendingSynchronizations[experimentID]?.id == id {
                Self.pendingSynchronizations[experimentID] = nil
            }
        }
        Self.pendingSynchronizations[experimentID] = (id, task)
        return task
    }

    @MainActor
    public func endAll(for experimentID: UUID) async {
        await scheduleSynchronization(experimentID, "", []).value
    }
}

extension TimerLiveActivityClient: DependencyKey {
    public static let liveValue = Self(
        synchronize: { experimentID, experimentTitle, timers in
            let activities = Activity<TimerActivityAttributes>.activities.filter {
                $0.attributes.experimentID == experimentID
            }

            let timerIDs = Set(timers.map(\.timerID))
            for activity in activities where !timerIDs.contains(activity.content.state.timerID) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }

            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            for timer in timers {
                let content = ActivityContent(
                    state: timer,
                    staleDate: timer.endsAt,
                    relevanceScore: -timer.endsAt.timeIntervalSinceReferenceDate
                )
                let matches = activities.filter { $0.content.state.timerID == timer.timerID }
                if let activity = matches.first {
                    await activity.update(content)
                    for duplicate in matches.dropFirst() {
                        await duplicate.end(nil, dismissalPolicy: .immediate)
                    }
                } else {
                    let attributes = TimerActivityAttributes(
                        experimentID: experimentID,
                        experimentTitle: experimentTitle
                    )
                    _ = try? Activity.request(
                        attributes: attributes, content: content, pushType: nil
                    )
                }
            }
        },
        dismissCompleted: { experimentID in
            for activity in Activity<TimerActivityAttributes>.activities
            where activity.attributes.experimentID == experimentID
                && activity.content.state.endsAt <= .now {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    )
}

extension DependencyValues {
    public var timerLiveActivityClient: TimerLiveActivityClient {
        get { self[TimerLiveActivityClient.self] }
        set { self[TimerLiveActivityClient.self] = newValue }
    }
}
