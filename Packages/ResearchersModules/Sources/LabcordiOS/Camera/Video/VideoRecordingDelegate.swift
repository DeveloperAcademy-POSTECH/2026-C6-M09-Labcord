import AVFoundation
import Foundation

nonisolated final class VideoRecordingDelegate: NSObject,
                                                AVCaptureFileOutputRecordingDelegate,
                                                @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var isCancelled = false
    private let onStarted: @Sendable () -> Void
    private let onCancelledStart: @Sendable () -> Void

    init(
        continuation: CheckedContinuation<URL, Error>,
        onStarted: @escaping @Sendable () -> Void,
        onCancelledStart: @escaping @Sendable () -> Void
    ) {
        self.continuation = continuation
        self.onStarted = onStarted
        self.onCancelledStart = onCancelledStart
    }

    func cancel() {
        lock.withLock { isCancelled = true }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        let cancelled = lock.withLock { isCancelled }
        if cancelled {
            onCancelledStart()
        } else {
            onStarted()
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let (continuation, cancelled) = lock.withLock {
            () -> (CheckedContinuation<URL, Error>?, Bool) in
            defer { self.continuation = nil }
            return (self.continuation, isCancelled)
        }

        guard let continuation else { return }

        let recordingSucceeded = (error as NSError?)?
            .userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true

        if cancelled {
            try? FileManager.default.removeItem(at: fileURL)
            continuation.resume(throwing: CancellationError())
        } else if let error, !recordingSucceeded {
            try? FileManager.default.removeItem(at: fileURL)
            continuation.resume(throwing: error)
        } else if FileManager.default.fileExists(atPath: fileURL.path) {
            continuation.resume(returning: fileURL)
        } else {
            continuation.resume(throwing: CameraSessionError.videoDataUnavailable)
        }
    }
}
