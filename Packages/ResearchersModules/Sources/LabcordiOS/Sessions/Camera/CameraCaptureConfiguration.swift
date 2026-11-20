import AVFoundation
import Foundation
import OSLog

nonisolated enum CameraCaptureConfiguration {
    private static let logger = Logger(subsystem: "Labcord", category: "Camera")

    nonisolated(nonsending) static func captureNativePhoto(
        output: AVCapturePhotoOutput,
        suppressShutterSound: Bool,
        usesMicrophone: Bool
    ) async throws -> Data {
        let audioSession = AVAudioSession.sharedInstance()
        let usesAudioInput = usesMicrophone || !audioSession.currentRoute.inputs.isEmpty
        let permitsRecordingSounds = audioSession.allowHapticsAndSystemSoundsDuringRecording
        let restoreRecordingAudio = usesAudioInput && !permitsRecordingSounds
            && setRecordingSystemSounds(true)
        var deadline: Task<Void, Never>?
        defer {
            deadline?.cancel()
            if restoreRecordingAudio {
                _ = setRecordingSystemSounds(false)
            }
        }

        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureDelegate(continuation: continuation)
            deadline = Task {
                try? await Task.sleep(for: .seconds(8))
                if !Task.isCancelled { delegate.timeout() }
            }
            let settings = photoSettings(
                suppressShutterSound: suppressShutterSound, output: output
            )
            logger.notice("""
                native shutter request=\(settings.uniqueID) audioInput=\(usesAudioInput) \
                suppressed=\(settings.isShutterSoundSuppressionEnabled)
                """)
            output.capturePhoto(with: settings, delegate: delegate)
        }
        logger.info("Photo captured: \(data.count) bytes")
        return data
    }

    private static func photoSettings(
        suppressShutterSound: Bool, output: AVCapturePhotoOutput
    ) -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        settings.isShutterSoundSuppressionEnabled = suppressShutterSound
            && output.isShutterSoundSuppressionSupported
        logger.debug("""
            Shutter sound requestedOff=\(suppressShutterSound) \
            supported=\(output.isShutterSoundSuppressionSupported)
            """)
        return settings
    }

    private static func setRecordingSystemSounds(_ allowed: Bool) -> Bool {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(allowed)
            return true
        } catch {
            logger.error("Capture sound setting failed: \(error.localizedDescription)")
            return false
        }
    }

    static func configureCaptureRotation(
        for connection: AVCaptureConnection?, camera activeCamera: AVCaptureDevice?
    ) {
        guard let connection, let activeCamera else { return }
        let angle = captureRotationAngle(camera: activeCamera)
        guard connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    static func captureRotationAngle(camera: AVCaptureDevice) -> CGFloat {
        AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
            .videoRotationAngleForHorizonLevelCapture
    }
}

public enum CameraSessionError: LocalizedError {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case photoDataUnavailable
    case alreadyCapturingPhoto
    case videoDataUnavailable
    case microphoneUnavailable
    case alreadyRecording

    public var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "카메라를 사용할 수 없습니다."
        case .cannotAddInput, .cannotAddOutput:
            return "카메라를 준비하지 못했습니다. 잠시 후 다시 시도해 주세요."
        case .photoDataUnavailable:
            return "촬영한 사진을 가져오지 못했습니다."
        case .alreadyCapturingPhoto:
            return "이미 사진을 촬영 중입니다."
        case .videoDataUnavailable:
            return "촬영한 영상을 가져오지 못했습니다."
        case .microphoneUnavailable:
            return "마이크를 사용할 수 없습니다."
        case .alreadyRecording:
            return "이미 영상을 촬영 중입니다."
        }
    }
}
