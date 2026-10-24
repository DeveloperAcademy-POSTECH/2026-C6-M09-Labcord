//
//  Experiment.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/24/26.
//

import Foundation
import SwiftData

@Model
public final class Experiment {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var startedAt: Date?
    public var endedAt: Date?
    public var status: ExperimentStatus
    public var procedure: ExperimentProtocol?
    
    @Relationship(deleteRule: .cascade)
    public var pauses: [Pause] = []
    
    @Relationship(deleteRule: .cascade)
    public var records: [ExperimentRecord] = []
    
    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        pauses: [Pause] = [],
        status: ExperimentStatus = .preparing,
        procedure: ExperimentProtocol? = nil,
        records: [ExperimentRecord] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pauses = pauses
        self.status = status
        self.procedure = procedure
        self.records = records
    }
}
