import AVFoundation
import Foundation
import OSLog

nonisolated final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let continuation: CheckedContinuation<Data, Error>
    private let completionLock = NSLock()
    private static let logger = Logger(subsystem: "Labcord", category: "Camera")
    private var processedPhoto: Result<Data, Error>?
    private var completed = false

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings
    ) {
        Self.logger.notice("native photo exposure request=\(resolvedSettings.uniqueID)")
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let result: Result<Data, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        } else {
            result = .failure(CameraSessionError.photoDataUnavailable)
        }
        completionLock.withLock {
            if !completed { processedPhoto = result }
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        finish(error: error)
    }

    func timeout() {
        finish(error: CameraSessionError.photoDataUnavailable)
    }

    private func finish(error: Error?) {
        completionLock.lock()
        guard !completed else {
            completionLock.unlock()
            return
        }
        completed = true
        let result = processedPhoto ?? .failure(error ?? CameraSessionError.photoDataUnavailable)
        processedPhoto = nil
        completionLock.unlock()
        continuation.resume(with: result)
    }
}
