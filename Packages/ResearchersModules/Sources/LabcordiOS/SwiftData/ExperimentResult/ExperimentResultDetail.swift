import Foundation
import LabcordShared

public struct ExperimentResultDetail: Equatable, Sendable {
    public struct Procedure: Equatable, Sendable {
        public let timerSeconds: [Int]
        public let materials: [String]
        public let samples: [String]
        public let glossaryTerms: [String]
        public let units: [String]
    }

    public struct PauseEntry: Equatable, Sendable {
        public let id: UUID
        public let pausedAt: Date
        public let resumedAt: Date?
    }

    public struct Record: Equatable, Sendable {
        public let id: UUID
        public let type: RecordType
        public let recordedAt: Date
        public let note: String
        public let filePath: String?
        public let transcript: String?
        public let timerDurationSeconds: Int?
        public let timerEndedAt: Date?
        public let timerPauses: [PauseEntry]
    }

    public struct StatusEntry: Equatable, Sendable {
        public let id: UUID
        public let status: ExperimentStatus
        public let date: Date
    }

    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let startedAt: Date?
    public let endedAt: [Date]
    public let status: ExperimentStatus
    public let mode: ExperimentMode
    public let procedure: Procedure?
    public let pauses: [PauseEntry]
    public let records: [Record]
    public let statusHistory: [StatusEntry]
}
