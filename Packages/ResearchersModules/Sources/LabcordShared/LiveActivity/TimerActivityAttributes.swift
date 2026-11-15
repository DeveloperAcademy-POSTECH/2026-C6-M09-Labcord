//
//  TimerActivityAttributes.swift
//  LabcordShared
//
//  Created by 정홍섭 on 11/14/26.
//

#if os(iOS)
import ActivityKit
import Foundation

nonisolated public struct TimerActivityAttributes: ActivityAttributes, Sendable {
    nonisolated public struct ContentState: Codable, Hashable, Sendable {
        public let timerID: UUID
        public let endsAt: Date
        public let durationSeconds: Int

        public init(timerID: UUID, endsAt: Date, durationSeconds: Int) {
            self.timerID = timerID
            self.endsAt = endsAt
            self.durationSeconds = durationSeconds
        }
    }

    public let experimentID: UUID
    public let experimentTitle: String

    public init(experimentID: UUID, experimentTitle: String) {
        self.experimentID = experimentID
        self.experimentTitle = experimentTitle
    }
}
#endif
