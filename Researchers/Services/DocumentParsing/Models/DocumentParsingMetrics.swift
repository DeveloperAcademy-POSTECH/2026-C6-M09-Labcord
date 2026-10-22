import Foundation

/// PDF 처리 구간의 이름. 각 구간은 다른 페이지의 작업·대기와 시간이 겹칠 수 있다.
/// 단계별 seconds의 합을 전체 처리 시간으로 해석하지 않는다.
nonisolated public enum DocumentParsingStage: String, Sendable, CaseIterable {
  case pdfOpen, pdfScan, pdfTables, pdfNativeText, pdfRender, pdfImages
  case pdfImageOCR, pdfPageOCR, pdfAssembly, pdfAwait, pdfSchedule
  case pdfPageOCRReuse
}

/// 문서 처리 시작을 기준으로 측정한 구간 하나. seconds는 벽시계 경과 시간이며 CPU 시간이 아니다.
nonisolated public struct DocumentStageTiming: Sendable, Equatable {
  public let stage: DocumentParsingStage
  /// 1부터 시작하는 관련 페이지. 문서 전체 구간은 nil이다.
  public let page: Int?
  /// 해당 PDF 처리 시작 이후 구간 시작까지 경과한 초.
  public let startOffsetSeconds: Double
  /// 이 구간에서 경과한 초. 다른 작업의 측정 구간과 겹칠 수 있다.
  public let seconds: Double
}

/// PDF 문서 하나의 실행 수치. 단계 간 겹침과 반환 결과의 메모리를 구분해서 해석한다.
nonisolated public struct DocumentParsingMetrics: Sendable, Equatable {
  /// PDF 열기부터 결과 조합까지 경과한 초. 배치 전체 실행 시간과는 다르다.
  public let wallSeconds: Double
  /// 이 문서에서 준비됐거나 OCR 중이던 페이지 수의 최대값.
  public let peakInFlightPages: Int
  /// 이 문서 작업량의 추정 최대값. 실제 프로세스 footprint 측정값이 아니다.
  public let peakEstimatedWorkingBytes: Int
  /// 시작 시각 순으로 정리한 단계별 기록. 합계를 wallSeconds와 비교하지 않는다.
  public let timings: [DocumentStageTiming]
  /// parseBatch에서만 제공하는 공용 예약 수치. 단일 parse는 nil이다.
  public var batchScheduling: DocumentBatchSchedulingMetrics?
}

/// 배치가 공유한 PDF 예약의 수치. 전체 배치가 끝난 뒤 각 PDF 결과에 같은 스냅샷을 담는다.
nonisolated public struct DocumentBatchSchedulingMetrics: Sendable, Equatable {
  /// 배치의 여러 PDF를 합쳐 동시에 예약한 페이지 수의 최대값.
  public let peakInFlightPages: Int
  /// 공용 풀에 예약한 추정 바이트의 최대값.
  public let peakEstimatedWorkingBytes: Int
  /// 반환 시점에 남은 예약 수. 정상 종료 뒤에는 0이어야 한다.
  public let activePages: Int
  /// 반환 시점의 대기 요청 수. 정상 종료 뒤에는 0이어야 한다.
  public let waitingRequests: Int
}

/// 같은 문서의 공통 시작 시각을 사용해 직렬 준비와 병렬 OCR 기록을 나중에 정렬한다.
nonisolated struct DocumentTiming: Sendable {
  let origin: ContinuousClock.Instant

  init(origin: ContinuousClock.Instant = .now) { self.origin = origin }

  var values: [DocumentStageTiming] = []

  /// 성공·오류 모두에서 defer로 실행 구간을 기록한다. 실패 여부 자체를 수치로 판별하지는 않는다.
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
