//
//  CameraSession.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/26/26.
//

import AVFoundation
import Dispatch
import Foundation

public actor CameraSession {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchSerialQueue(
        label: "com.researchers.camera.capture"
    )
    private let handTrackingQueue = DispatchQueue(
        label: "com.researchers.camera.hand-tracking",
        qos: .userInitiated
    )

    nonisolated public var unownedExecutor: UnownedSerialExecutor {
        sessionQueue.asUnownedSerialExecutor()
    }

    private var isConfigured = false
    private var activeCamera: AVCaptureDevice?
    private var cachedPreviewConnector: CameraPreviewConnector?
    private let photoOutput = AVCapturePhotoOutput()
    private var photoDelegate: PhotoCaptureDelegate?
    private let movieOutput = AVCaptureMovieFileOutput()
    private var microphoneInput: AVCaptureDeviceInput?
    private var videoDelegate: VideoRecordingDelegate?
    private let handEventHub: CameraHandEventHub
    private let handDetector: CameraHandDetector
    private var activeOwners: Set<UUID> = []
    private var pendingStop: Task<Void, Never>?

    public init() {
        let hub = CameraHandEventHub()
        handEventHub = hub
        handDetector = CameraHandDetector { hub.emit($0) }
    }

    public func configureCamera() throws {
        guard !isConfigured else { return }

        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw PermissionAccessError(.camera)
        }

        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ) else {
            throw CameraSessionError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard session.canAddInput(input) else {
            throw CameraSessionError.cannotAddInput
        }

        session.addInput(input)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(handDetector, queue: handTrackingQueue)
        guard session.canAddOutput(videoOutput) else {
            session.removeInput(input)
            throw CameraSessionError.cannotAddOutput
        }
        session.addOutput(videoOutput)
        guard session.canAddOutput(photoOutput) else {
            session.removeOutput(videoOutput)
            session.removeInput(input)
            throw CameraSessionError.cannotAddOutput
        }
        session.addOutput(photoOutput)
        activeCamera = camera
        isConfigured = true
    }

    public func activate(owner: UUID) throws {
        pendingStop?.cancel()
        pendingStop = nil
        try configureCamera()
        if AVAudioApplication.shared.recordPermission == .granted {
            try? prepareVideoRecording()
        }

        if activeOwners.isEmpty {
            // Clear a held pose before a returning view subscribes to hand events.
            handTrackingQueue.sync { [handDetector] in handDetector.reset() }
        }
        if !session.isRunning {
            session.startRunning()
        }
        activeOwners.insert(owner)
    }

    public func deactivate(owner: UUID) {
        activeOwners.remove(owner)
        guard activeOwners.isEmpty else { return }
        pendingStop?.cancel()
        pendingStop = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(700))
                await self?.stopIfUnused()
            } catch {
                return
            }
        }
    }

    private func stopIfUnused() {
        guard activeOwners.isEmpty else { return }
        pendingStop = nil
        cancelVideoRecording()
        if session.isRunning {
            session.stopRunning()
        }
        resetHandTracking()
    }

    public func switchCamera() async throws {
        try configureCamera()

        guard let currentInput = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput })
                .first(where: { $0.ports.contains { $0.mediaType == .video } }),
              let activeCamera else {
            throw CameraSessionError.cameraUnavailable
        }

        let nextPosition: AVCaptureDevice.Position = activeCamera.position == .front ? .back : .front
        guard let nextCamera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: nextPosition
        ) else {
            throw CameraSessionError.cameraUnavailable
        }

        let nextInput = try AVCaptureDeviceInput(device: nextCamera)
        session.beginConfiguration()

        session.removeInput(currentInput)
        guard session.canAddInput(nextInput) else {
            session.addInput(currentInput)
            session.commitConfiguration()
            throw CameraSessionError.cannotAddInput
        }

        session.addInput(nextInput)
        self.activeCamera = nextCamera
        session.commitConfiguration()
        resetHandTracking()
        if let cachedPreviewConnector {
            await cachedPreviewConnector.updateDevice(nextCamera)
        }
    }

    public func handEvents() -> AsyncStream<CameraHandEvent> {
        handEventHub.stream()
    }

    private func resetHandTracking() {
        handTrackingQueue.async { [handDetector] in handDetector.reset() }
    }

    public func capturePhoto() async throws -> Data {
        guard session.isRunning else { throw CameraSessionError.cameraUnavailable }
        guard photoDelegate == nil else { throw CameraSessionError.alreadyCapturingPhoto }
        defer { photoDelegate = nil }

        configureCaptureRotation(for: photoOutput.connection(with: .video))

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureDelegate(continuation: continuation)
            photoDelegate = delegate
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
        }
    }

    public func recordVideo(onStarted: @escaping @Sendable () -> Void) async throws -> URL {
        try Task.checkCancellation()
        guard session.isRunning else { throw CameraSessionError.cameraUnavailable }
        guard videoDelegate == nil else { throw CameraSessionError.alreadyRecording }
        try prepareVideoRecording()
        defer { videoDelegate = nil }
        try Task.checkCancellation()

        configureCaptureRotation(for: movieOutput.connection(with: .video))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-\(UUID().uuidString).mov")
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let delegate = VideoRecordingDelegate(
                    continuation: continuation,
                    onStarted: onStarted
                ) { [weak self] in
                        Task { await self?.cancelVideoRecording() }
                    }
                videoDelegate = delegate
                movieOutput.startRecording(to: url, recordingDelegate: delegate)
            }
        } onCancel: {
            Task { await self.cancelVideoRecording() }
        }
    }

    public func cancelVideoRecording() {
        guard let videoDelegate else { return }
        videoDelegate.cancel()
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
    }

    public func discardVideo(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    public func prepareVideoRecording() throws {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw PermissionAccessError(.microphone)
        }
        guard isConfigured else { throw CameraSessionError.cameraUnavailable }
        guard microphoneInput == nil else { return }
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            throw CameraSessionError.microphoneUnavailable
        }
        let input = try AVCaptureDeviceInput(device: microphone)

        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraSessionError.cannotAddInput
        }
        session.addInput(input)
        guard session.canAddOutput(movieOutput) else {
            session.removeInput(input)
            session.commitConfiguration()
            throw CameraSessionError.cannotAddOutput
        }
        session.addOutput(movieOutput)
        movieOutput.maxRecordedDuration = CMTime(
            seconds: Double(VideoRecordingSettings.durationSeconds),
            preferredTimescale: 600
        )
        session.commitConfiguration()
        guard movieOutput.connection(with: .audio) != nil else {
            session.beginConfiguration()
            session.removeOutput(movieOutput)
            session.removeInput(input)
            session.commitConfiguration()
            throw CameraSessionError.microphoneUnavailable
        }
        microphoneInput = input
    }

    private func configureCaptureRotation(for connection: AVCaptureConnection?) {
        guard let connection, let activeCamera else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: activeCamera,
            previewLayer: nil
        )
        let angle = coordinator.videoRotationAngleForHorizonLevelCapture
        guard connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    public func previewConnector() -> CameraPreviewConnector {
        if let cachedPreviewConnector {
            return cachedPreviewConnector
        }

        let connector = CameraPreviewConnector(session: session, device: activeCamera)
        cachedPreviewConnector = connector
        return connector
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
