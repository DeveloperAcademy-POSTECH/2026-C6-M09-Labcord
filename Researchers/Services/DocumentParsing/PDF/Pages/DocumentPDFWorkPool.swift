import Foundation

/// 배치 호출 하나가 소유한다. PDFKit 객체 없이 준비·OCR 작업의 수와 추정 바이트만 관리한다.
actor DocumentPDFWorkPool {
  private struct Waiter {
    let id: UUID
    let bytes: Int
    let continuation: CheckedContinuation<UUID, Error>
  }

  private let maximumPages: Int
  private let targetBytes: Int
  private var active: [UUID: Int] = [:]
  private var waiting: [Waiter] = []
  private var bytes = 0
  private var peakPages = 0
  private var peakBytes = 0

  init(options: DocumentParserOptions) {
    maximumPages = max(1, min(options.maximumConcurrentPDFPages,
                              ProcessInfo.processInfo.activeProcessorCount))
    targetBytes = max(1, options.pdfWorkingMemoryTargetBytes)
  }

  func acquire(estimatedBytes: Int) async throws -> UUID {
    try Task.checkCancellation()
    let id = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        waiting.append(Waiter(id: id, bytes: bounded(estimatedBytes), continuation: continuation))
        drain()
      }
    } onCancel: {
      // 취소 핸들러는 동기이므로 actor의 대기열 제거만 짧은 Task로 전달한다.
      Task { @concurrent in await self.cancel(id) }
    }
  }

  func resize(_ id: UUID, actualBytes: Int) {
    guard let previous = active[id] else { return }
    let actual = bounded(actualBytes)
    bytes += actual - previous
    active[id] = actual
    peakBytes = max(peakBytes, bytes)
  }

  func release(_ id: UUID) {
    guard let released = active.removeValue(forKey: id) else { return }
    bytes -= released
    drain()
  }

  func snapshot() -> DocumentBatchSchedulingMetrics {
    DocumentBatchSchedulingMetrics(
      peakInFlightPages: peakPages, peakEstimatedWorkingBytes: peakBytes,
      activePages: active.count, waitingRequests: waiting.count)
  }

  private func bounded(_ value: Int) -> Int {
    max(1, min(value, Int.max / (maximumPages + 1)))
  }

  private func cancel(_ id: UUID) {
    guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
    waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    drain()
  }

  private func drain() {
    while let first = waiting.first, active.count < maximumPages {
      // 목표보다 큰 한 페이지도 단독으로 처리한다. FIFO로 큰 요청의 기아를 막는다.
      guard active.isEmpty || first.bytes <= max(0, targetBytes - bytes) else { return }
      waiting.removeFirst()
      active[first.id] = first.bytes
      bytes += first.bytes
      peakPages = max(peakPages, active.count)
      peakBytes = max(peakBytes, bytes)
      first.continuation.resume(returning: first.id)
    }
  }
}

nonisolated enum DocumentPDFScheduling {
  @TaskLocal static var pool: DocumentPDFWorkPool?

  static func acquire(
    estimatedBytes: Int, page: Int, timing: inout DocumentTiming
  ) async throws -> UUID? {
    guard let pool else { return nil }
    let start = ContinuousClock.now
    defer { timing.record(.pdfSchedule, page: page, start: start) }
    return try await pool.acquire(estimatedBytes: estimatedBytes)
  }

  static func recognize(_ page: DocumentPDFPreparedPage, lease: UUID?) async throws
    -> DocumentPDFPreparedPage {
    do {
      let result = try await DocumentPDFPageParser.recognize(page)
      if let lease { await pool?.release(lease) }
      return result
    } catch {
      if let lease { await pool?.release(lease) }
      throw error
    }
  }
}
