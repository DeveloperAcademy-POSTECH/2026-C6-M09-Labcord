import Foundation

nonisolated public enum DocumentParsingStage: String, Sendable, CaseIterable {
  case pdfOpen, pdfScan, pdfTables, pdfNativeText, pdfRender, pdfImages
  case pdfImageOCR, pdfPageOCR, pdfAssembly, pdfAwait, pdfSchedule
  case pdfPageOCRReuse
}

nonisolated public struct DocumentStageTiming: Sendable, Equatable {
  public let stage: DocumentParsingStage
  public let page: Int?
  public let startOffsetSeconds: Double
  public let seconds: Double
}

nonisolated public struct DocumentParsingMetrics: Sendable, Equatable {
  public let wallSeconds: Double
  public let peakInFlightPages: Int
  public let peakEstimatedWorkingBytes: Int
  public let timings: [DocumentStageTiming]
  public var batchScheduling: DocumentBatchSchedulingMetrics?
}

nonisolated public struct DocumentBatchSchedulingMetrics: Sendable, Equatable {
  public let peakInFlightPages: Int
  public let peakEstimatedWorkingBytes: Int
  public let activePages: Int
  public let waitingRequests: Int
}

nonisolated struct DocumentTiming: Sendable {
  let origin: ContinuousClock.Instant

  init(origin: ContinuousClock.Instant = .now) { self.origin = origin }

  var values: [DocumentStageTiming] = []

  mutating func measure<T>(
    _ stage: DocumentParsingStage, page: Int? = nil, _ operation: () throws -> T
  ) rethrows -> T {
    let start = ContinuousClock.now
    defer { record(stage, page: page, start: start) }
    return try operation()
  }

  mutating func record(
    _ stage: DocumentParsingStage, page: Int? = nil, start: ContinuousClock.Instant
  ) {
    values.append(DocumentStageTiming(
      stage: stage, page: page, startOffsetSeconds: Self.seconds(origin.duration(to: start)),
      seconds: Self.seconds(start.duration(to: .now))))
  }

  static func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
  }
}
