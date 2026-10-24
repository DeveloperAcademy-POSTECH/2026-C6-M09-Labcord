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
    public var timerEndedAt: Date?

    public init(
        id: UUID = UUID(),
        type: RecordType,
        recordedAt: Date,
        note: String,
        filePath: String? = nil,
        transcript: String? = nil,
        timerEndedAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.recordedAt = recordedAt
        self.note = note
        self.filePath = filePath
        self.transcript = transcript
        self.timerEndedAt = timerEndedAt
    }
}
