import AVFoundation
import Dispatch
import Foundation
import OSLog

public actor CameraSession {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchSerialQueue(label: "com.researchers.camera.capture")
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
    private var isCapturingPhoto = false
    #if DEBUG
    private let silentPhoto = SilentPreviewPhotoCapture()
    #endif
    private let movieOutput = AVCaptureMovieFileOutput()
    private var microphoneInput: AVCaptureDeviceInput?
    private var videoDelegate: VideoRecordingDelegate?
    private var videoSessionID: UUID?
    private let handEventHub: CameraHandEventHub
    private let handOverlayHub: CameraHandOverlayHub
    private let handDetector: CameraHandDetector
    private var activeOwners: Set<UUID> = []
    private var isSuspended = false
    private var pendingStop: Task<Void, Never>?

    public init() {
        let hub = CameraHandEventHub()
        let overlayHub = CameraHandOverlayHub()
        handEventHub = hub
        handOverlayHub = overlayHub
        #if DEBUG
        let onFrame = silentPhoto.receive
        #else
        let onFrame: ((CVPixelBuffer, CGFloat) -> Void)? = nil
        #endif
        handDetector = CameraHandDetector(
            queue: handTrackingQueue,
            onFrame: onFrame,
            onHold: { hub.emit($0) },
            onOverlay: { overlayHub.emit($0) }
        )
    }

    public func configureCamera() throws {
        try requireCameraPermission()
        guard !isConfigured else { return }

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
        try Task.checkCancellation()
        try configureCamera()
        pendingStop?.cancel()
        pendingStop = nil
        isSuspended = false

        if activeOwners.isEmpty {
            handTrackingQueue.sync { [handDetector] in handDetector.reset() }
        }
        activeOwners.insert(owner)
        startSessionIfPossible()
        guard session.isRunning || session.isInterrupted else {
            throw CameraSessionError.cameraUnavailable
        }
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

    public func suspend() {
        guard !Task.isCancelled, !activeOwners.isEmpty else { return }
        isSuspended = true
        if session.isRunning || session.isInterrupted {
            session.stopRunning()
        }
        resetHandTracking()
    }

    private func stopIfUnused() {
        guard activeOwners.isEmpty else { return }
        pendingStop = nil
        cancelVideoRecording()
        if session.isRunning || session.isInterrupted {
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

        let nextPosition: AVCaptureDevice.Position = activeCamera.position == .front
        ? .back
        : .front
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
        handOverlayHub.emit(.init(
            segments: [],
            joints: [],
            imageSize: .zero,
            videoRotationAngle: 0,
            isVideoMirrored: false
        ))
        handTrackingQueue.async { [handDetector] in handDetector.reset() }
    }
}

extension CameraSession {
    public func capturePhoto(suppressShutterSound: Bool) async throws -> Data {
        try await waitForCaptureSession()
        guard !isCapturingPhoto else { throw CameraSessionError.alreadyCapturingPhoto }
        guard videoSessionID == nil else { throw CameraSessionError.alreadyRecording }
        isCapturingPhoto = true
        defer { isCapturingPhoto = false }
        #if DEBUG
        if suppressShutterSound && !photoOutput.isShutterSoundSuppressionSupported {
            return try await silentPhoto.capture(camera: activeCamera)
        }
        #endif
        CameraCaptureConfiguration.configureCaptureRotation(
            for: photoOutput.connection(with: .video), camera: activeCamera
        )
        return try await CameraCaptureConfiguration.captureNativePhoto(
            output: photoOutput,
            suppressShutterSound: suppressShutterSound,
            usesMicrophone: microphoneInput != nil
        )
    }

    public func recordVideo(
        id: UUID, onStarted: @escaping @Sendable () -> Void
    ) async throws -> URL {
        try requireCameraPermission()
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw PermissionAccessError(.microphone)
        }
        let deadline = ContinuousClock().now + .milliseconds(1500)
        try await waitForCaptureSession(until: deadline)
        guard !isCapturingPhoto else { throw CameraSessionError.alreadyCapturingPhoto }
        guard videoSessionID == nil else { throw CameraSessionError.alreadyRecording }
        videoSessionID = id
        defer {
            videoDelegate = nil
            videoSessionID = nil
            releaseVideoInputs()
        }
        try prepareVideoRecording()
        try await waitForCaptureSession(until: deadline, output: movieOutput)
        guard movieOutput.connection(with: .audio)?.isActive == true else {
            throw CameraSessionError.microphoneUnavailable
        }

        CameraCaptureConfiguration.configureCaptureRotation(
            for: movieOutput.connection(with: .video), camera: activeCamera
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("video-\(UUID().uuidString).mov")
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let delegate = VideoRecordingDelegate(
                    continuation: continuation,
                    onStarted: onStarted
                ) { [weak self] in
                        Task { await self?.cancelVideoRecording(id: id) }
                    }
                videoDelegate = delegate
                movieOutput.startRecording(to: url, recordingDelegate: delegate)
            }
        } onCancel: {
            Task { await self.cancelVideoRecording(id: id) }
        }
    }

    public func cancelVideoRecording(id: UUID? = nil) {
        guard id == nil || id == videoSessionID, let videoDelegate else { return }
        videoDelegate.cancel()
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
    }

    public func discardVideo(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    public func stopVideoRecording(id: UUID) {
        guard videoSessionID == id, movieOutput.isRecording else { return }
        movieOutput.stopRecording()
    }

    private func prepareVideoRecording() throws {
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
}

private extension CameraSession {
    static let logger = Logger(subsystem: "Labcord", category: "Camera")

    func requireCameraPermission() throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw PermissionAccessError(.camera)
        }
    }

    func startSessionIfPossible() {
        if !session.isRunning && !session.isInterrupted {
            session.startRunning()
        }
    }

    func waitForCaptureSession(
        until deadline: ContinuousClock.Instant = ContinuousClock().now + .milliseconds(1500),
        output: AVCaptureOutput? = nil
    ) async throws {
        let clock = ContinuousClock()
        var requestedStart = false
        repeat {
            try Task.checkCancellation()
            try requireCameraPermission()
            guard !activeOwners.isEmpty, !isSuspended else {
                throw CameraSessionError.cameraUnavailable
            }
            if !requestedStart && !session.isRunning && !session.isInterrupted {
                requestedStart = true
                startSessionIfPossible()
            }
            if session.isRunning, !session.isInterrupted,
               (output ?? photoOutput).connection(with: .video)?.isActive == true { return }
            try await clock.sleep(for: .milliseconds(50))
        } while clock.now < deadline
        Self.logger.error("""
            Capture session not ready running=\(self.session.isRunning) \
            interrupted=\(self.session.isInterrupted)
            """)
        throw CameraSessionError.cameraUnavailable
    }

    func releaseVideoInputs() {
        guard let microphoneInput else { return }
        session.beginConfiguration()
        session.removeOutput(movieOutput)
        session.removeInput(microphoneInput)
        self.microphoneInput = nil
        session.commitConfiguration()
    }
}

extension CameraSession {
    public func isRunning() -> Bool {
        session.isRunning
    }

    public func previewConnector() -> CameraPreviewConnector {
        if let cachedPreviewConnector {
            return cachedPreviewConnector
        }

        let connector = CameraPreviewConnector(
            session: session,
            device: activeCamera,
            handOverlayHub: handOverlayHub
        )
        cachedPreviewConnector = connector
        return connector
    }
}
