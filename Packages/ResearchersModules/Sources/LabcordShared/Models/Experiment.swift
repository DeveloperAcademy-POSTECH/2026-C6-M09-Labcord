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
    public private(set) var endedAt: [Date] = []
    public private(set) var status: ExperimentStatus
    public private(set) var mode: ExperimentMode
    public var procedure: ExperimentProtocol?

    @Relationship(deleteRule: .cascade)
    public var pauses: [Pause] = []

    @Relationship(deleteRule: .cascade)
    public var records: [ExperimentRecord] = []

    @Relationship(deleteRule: .cascade)
    public private(set) var statusHistory: [ExperimentStatusEntry] = []

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        startedAt: Date? = nil,
        endedAt: [Date] = [],
        pauses: [Pause] = [],
        status: ExperimentStatus = .preparing,
        mode: ExperimentMode = .free,
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
        self.mode = mode
        self.procedure = procedure
        self.records = records
        self.statusHistory = [ExperimentStatusEntry(status: status, date: createdAt)]
    }

    public func markInProgress(at date: Date, entryID: UUID) {
        guard !statusHistory.contains(where: { $0.id == entryID }) else { return }
        status = .inProgress
        statusHistory.append(
            ExperimentStatusEntry(id: entryID, status: .inProgress, date: date)
        )
    }

    public func complete(at date: Date) {
        guard status != .completed else { return }
        endedAt.append(date)
        status = .completed
        statusHistory.append(ExperimentStatusEntry(status: .completed, date: date))
    }
}
