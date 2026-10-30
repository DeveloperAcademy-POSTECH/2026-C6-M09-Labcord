import Foundation
import SwiftData

@Model
public final class ExperimentStatusEntry {
    public var id: UUID
    public var status: ExperimentStatus
    public var date: Date

    public init(id: UUID = UUID(), status: ExperimentStatus, date: Date = .now) {
        self.id = id
        self.status = status
        self.date = date
    }
}
