// 검사 경계: 테스트는 실제 reducer와 명시적인 기록 의존성을 사용한다.
import Foundation

extension WatchRecordingUIBridge {
    static let live = Self(
        perform: { _ in throw WatchIntentRuntimeError.notReady },
        updates: { AsyncStream { $0.finish() } }
    )
}
