import AVFoundation
import Foundation

nonisolated final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let continuation: CheckedContinuation<Data, Error>
    private let completionLock = NSLock()
    private var completed = false

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            finish(.failure(error))
        } else if let data = photo.fileDataRepresentation() {
            finish(.success(data))
        } else {
            finish(.failure(CameraSessionError.photoDataUnavailable))
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        guard let error else { return }
        finish(.failure(error))
    }

    private func finish(_ result: Result<Data, Error>) {
        completionLock.lock()
        guard !completed else {
            completionLock.unlock()
            return
        }
        completed = true
        completionLock.unlock()
        continuation.resume(with: result)
    }
}
