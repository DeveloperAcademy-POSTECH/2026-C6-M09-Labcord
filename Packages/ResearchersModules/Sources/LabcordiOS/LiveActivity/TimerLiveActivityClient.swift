import ActivityKit
import ComposableArchitecture
import Foundation
import LabcordShared

public struct TimerLiveActivityClient: Sendable {
    public var synchronize: @MainActor @Sendable (
        UUID, String, TimerActivityAttributes.ContentState?
    ) async -> Void

    public init(
        synchronize: @escaping @MainActor @Sendable (
            UUID, String, TimerActivityAttributes.ContentState?
        ) async -> Void
    ) {
        self.synchronize = synchronize
    }
}

extension TimerLiveActivityClient: DependencyKey {
    public static let liveValue = Self { experimentID, experimentTitle, timer in
        let activities = Activity<TimerActivityAttributes>.activities.filter {
            $0.attributes.experimentID == experimentID
        }

        guard let timer else {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let content = ActivityContent(state: timer, staleDate: timer.endsAt)

        if let activity = activities.first {
            await activity.update(content)
            for duplicate in activities.dropFirst() {
                await duplicate.end(nil, dismissalPolicy: .immediate)
            }
        } else {
            let attributes = TimerActivityAttributes(
                experimentID: experimentID,
                experimentTitle: experimentTitle
            )
            _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        }
    }
}

extension DependencyValues {
    public var timerLiveActivityClient: TimerLiveActivityClient {
        get { self[TimerLiveActivityClient.self] }
        set { self[TimerLiveActivityClient.self] = newValue }
    }
}
