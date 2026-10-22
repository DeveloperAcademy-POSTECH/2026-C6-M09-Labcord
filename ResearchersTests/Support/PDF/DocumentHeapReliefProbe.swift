import Darwin
import Foundation
import Synchronization

@testable import Researchers

/// 할당기에서 반환할 수 있는 빈 페이지가 고점에 기여하는지 진단한다. 앱 코드에는 쓰지 않는다.
/// 메모리 반환 가능성을 비교하는 테스트 전용 진단이다. 제품 파서에 주기적인 메모리 정리를 추가하는 코드가 아니다.
nonisolated final class DocumentHeapReliefProbe: Sendable {
  private struct State: Sendable {
    var started = false
    var before: UInt64 = 0
    var after: UInt64 = 0
    var released = 0
    var seconds = 0.0
  }
  private let state = Mutex(State())

  func progress(_ event: DocumentProgress) {
    guard event.inputIndex == 0, event.phase == .recognizingText,
      event.fractionCompleted >= 0.82 else { return }
    let shouldRun = state.withLock { value in
      guard !value.started else { return false }
      value.started = true
      return true
    }
    guard shouldRun else { return }
    let before = DocumentFootprint.bytes() ?? 0
    let start = ContinuousClock.now
    let released = malloc_zone_pressure_relief(nil, 0)
    let seconds = DocumentFootprint.seconds(start.duration(to: .now))
    let after = DocumentFootprint.bytes() ?? 0
    state.withLock {
      $0.before = before
      $0.after = after
      $0.released = released
      $0.seconds = seconds
    }
  }

  var report: [String: Any] {
    state.withLock {
      ["started": $0.started, "beforeFootprintBytes": $0.before,
       "afterFootprintBytes": $0.after, "releasedBytes": $0.released, "seconds": $0.seconds]
    }
  }
}
