import Dispatch

/// 동기 PDF/Vision 호출이 Swift 협력 스레드 풀의 진행을 막지 않도록 분리한다.
/// 실행 작업 수와 래스터 수는 상위 파이프라인의 작업창으로 제한한다.
/// 실제 동시 실행 수는 이 큐가 아니라 상위 파이프라인과 공용 작업 예산이 제한한다.
nonisolated final class DocumentPDFTaskExecutor: TaskExecutor {
  static let shared = DocumentPDFTaskExecutor()
  private let queue = DispatchQueue(
    label: "DocumentParsing.PDF.OCR", qos: .userInitiated, attributes: .concurrent)

  func enqueue(_ job: consuming ExecutorJob) {
    let job = UnownedJob(job)
    queue.async { job.runSynchronously(on: self.asUnownedTaskExecutor()) }
  }
}
