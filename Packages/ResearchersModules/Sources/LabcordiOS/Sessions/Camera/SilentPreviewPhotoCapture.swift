#if DEBUG
import AVFoundation
import CoreImage
import OSLog
import Synchronization

nonisolated final class SilentPreviewPhotoCapture: Sendable {
    private struct Request: Sendable {
        let rotation: CGFloat
        let continuation: AsyncStream<Data>.Continuation
    }

    private static let logger = Logger(subsystem: "Labcord", category: "Camera")
    private let context = CIContext()
    private let pending = Mutex<Request?>(nil)

    func capture(camera: AVCaptureDevice?) async throws -> Data {
        try Task.checkCancellation()
        let rotation = camera.map(CameraCaptureConfiguration.captureRotationAngle) ?? 0
        let (stream, continuation) = AsyncStream<Data>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        pending.withLock { $0 = Request(rotation: rotation, continuation: continuation) }
        defer {
            pending.withLock { $0 = nil }
            continuation.finish()
        }

        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                for await data in stream { return data }
                throw CameraSessionError.photoDataUnavailable
            }
            group.addTask {
                try await Task.sleep(for: .milliseconds(1500))
                throw CameraSessionError.photoDataUnavailable
            }
            defer { group.cancelAll() }
            guard let data = try await group.next() else {
                throw CameraSessionError.photoDataUnavailable
            }
            try Task.checkCancellation()
            return data
        }
    }

    func receive(_ pixelBuffer: CVPixelBuffer, rotation: CGFloat) {
        let request = pending.withLock {
            let request = $0
            $0 = nil
            return request
        }
        guard let request else { return }
        defer { request.continuation.finish() }
        let quarterTurns = Int(((request.rotation - rotation) / 90).rounded())
        let orientations: [CGImagePropertyOrientation] = [.up, .right, .down, .left]
        let image = CIImage(cvPixelBuffer: pixelBuffer)
            .oriented(orientations[(quarterTurns % 4 + 4) % 4])
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let data = context.jpegRepresentation(of: image, colorSpace: colorSpace) else {
            return
        }
        Self.logger.notice("Silent preview photo captured: \(data.count) bytes")
        request.continuation.yield(data)
    }
}
#endif
