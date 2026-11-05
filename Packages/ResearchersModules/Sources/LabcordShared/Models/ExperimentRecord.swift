//
//  ExperimentRecord.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/24/26.
//

import Foundation
import SwiftData

@Model
public final class ExperimentRecord {
    public var id: UUID
    public var type: RecordType
    public var recordedAt: Date
    public var note: String
    public var filePath: String?
    public var transcript: String?
    public var timerEventNotesData: Data?
    public var hiddenTimerEventIDsData: Data?
    public var timerDurationSeconds: Int?
    public var timerEndedAt: Date?

    @Relationship(deleteRule: .cascade)
    public var timerPauses: [Pause] = []

    public init(
        id: UUID = UUID(),
        type: RecordType,
        recordedAt: Date,
        note: String,
        filePath: String? = nil,
        transcript: String? = nil,
        timerEventNotesData: Data? = nil,
        hiddenTimerEventIDsData: Data? = nil,
        timerDurationSeconds: Int? = nil,
        timerEndedAt: Date? = nil,
        timerPauses: [Pause] = []
    ) {
        self.id = id
        self.type = type
        self.recordedAt = recordedAt
        self.note = note
        self.filePath = filePath
        self.transcript = transcript
        self.timerEventNotesData = timerEventNotesData
        self.hiddenTimerEventIDsData = hiddenTimerEventIDsData
        self.timerDurationSeconds = timerDurationSeconds
        self.timerEndedAt = timerEndedAt
        self.timerPauses = timerPauses
    }
}
