import Foundation
import LabcordShared
import SwiftData

nonisolated public struct RecentProtocolEntry: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let timerSeconds: [Int]
    public let materials: [String]
    public let samples: [String]
    public let glossaryTerms: [String]
    public let units: [String]
}

@MainActor
enum RecentProtocolRepository {
    static func load() throws -> [RecentProtocolEntry] {
        let context = try ExperimentStore.shared.makeContext()
        let experiments = try context.fetch(FetchDescriptor<Experiment>())
        let entries = experiments.compactMap { experiment -> RecentProtocolEntry? in
            guard let procedure = experiment.procedure else { return nil }
            return RecentProtocolEntry(
                id: experiment.id,
                title: experiment.title,
                createdAt: experiment.createdAt,
                timerSeconds: procedure.timerSeconds,
                materials: procedure.materials,
                samples: procedure.samples,
                glossaryTerms: procedure.glossaryTerms,
                units: procedure.units
            )
        }
        return distinctNewestFirst(entries)
    }

    static func distinctNewestFirst(_ entries: [RecentProtocolEntry]) -> [RecentProtocolEntry] {
        let ordered = entries.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        var keys = Set<ProtocolContentKey>()
        return ordered.filter { keys.insert(ProtocolContentKey($0)).inserted }
    }
}

private struct ProtocolContentKey: Hashable {
    let timerSeconds: [Int]
    let materials: [String]
    let samples: [String]
    let glossaryTerms: [String]
    let units: [String]

    init(_ entry: RecentProtocolEntry) {
        timerSeconds = entry.timerSeconds
        materials = Self.normalized(entry.materials)
        samples = Self.normalized(entry.samples)
        glossaryTerms = Self.normalized(entry.glossaryTerms)
        units = entry.units.map { unit in
            ProtocolDocumentUnitExtractor.key(unit.trimmingCharacters(in: .whitespacesAndNewlines))
        }.sorted()
    }

    private static func normalized(_ terms: [String]) -> [String] {
        terms.map { term in
            term.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map { scalar in
                if (65...90).contains(scalar.value),
                   let folded = Unicode.Scalar(scalar.value + 32) {
                    return String(folded)
                }
                return String(scalar)
            }.joined()
        }.sorted()
    }
}
