#if targetEnvironment(simulator)
import AVFoundation
import Foundation
import UIKit

actor GreenScreenCamera {
    private var owners: Set<UUID> = []
    private var recordingID: UUID?
    private var stopRequested = false
    private var audioRecorder: AVAudioRecorder?

    var isRunning: Bool { !owners.isEmpty }

    func activate(_ owner: UUID) { owners.insert(owner) }

    func deactivate(_ owner: UUID) {
        owners.remove(owner)
        if owners.isEmpty { cancelVideoRecording() }
    }

    func capturePhoto() async throws -> Data {
        guard isRunning else { throw CameraSessionError.cameraUnavailable }
        #if DEBUG
        if let position = await MainActor.run(body: {
            RecordingDemoVideoPreview.capturePosition()
        }) {
            let asset = AVURLAsset(url: position.url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 24)
            generator.requestedTimeToleranceAfter = .zero
            let duration = try await asset.load(.duration)
            let lastTime = CMTimeSubtract(duration, CMTime(value: 1, timescale: 600))
            let captureTime = min(position.time, max(.zero, lastTime))
            let frame = try await generator.image(at: captureTime).image
            let data = await MainActor.run {
                let image = UIImage(cgImage: frame)
                let preview = position.previewSize
                guard preview.width > 0, preview.height > 0 else { return nil as Data? }
                let size = CGSize(width: 720, height: 720 * preview.height / preview.width)
                let scale = max(size.width / image.size.width, size.height / image.size.height)
                let drawSize = CGSize(width: image.size.width * scale,
                                      height: image.size.height * scale)
                let rectangle = CGRect(x: (size.width - drawSize.width) / 2,
                                       y: (size.height - drawSize.height) / 2,
                                       width: drawSize.width, height: drawSize.height)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                return UIGraphicsImageRenderer(size: size, format: format)
                    .image { _ in image.draw(in: rectangle) }.jpegData(compressionQuality: 0.9)
            }
            guard isRunning, let data else { throw CameraSessionError.cameraUnavailable }
            return data
        }
        #endif
        let data = await MainActor.run {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 1280))
            let image = renderer.image { context in
                UIColor.green.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 720, height: 1280))
            }
            return image.jpegData(compressionQuality: 0.9)
        }
        guard isRunning, let data else {
            throw CameraSessionError.cameraUnavailable
        }
        return data
    }

    func recordVideo(onStarted: @escaping @Sendable () -> Void) async throws -> URL {
        guard isRunning else { throw CameraSessionError.cameraUnavailable }
        guard recordingID == nil else { throw CameraSessionError.alreadyRecording }
        let id = UUID()
        recordingID = id
        stopRequested = false
        defer { if recordingID == id { recordingID = nil } }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw PermissionAccessError(.microphone)
        }
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("green-audio-\(id.uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }
        let recorder = try startDemoAudioRecording(at: audioURL)
        audioRecorder = recorder
        defer { stopAudioRecording(recorder) }
        #if DEBUG
        let previewPosition = await MainActor.run { RecordingDemoVideoPreview.capturePosition() }
        #endif
        let started = ContinuousClock.now
        onStarted()
        try await waitForRecording(id: id, started: started)
        recorder?.stop()
        let elapsed = started.duration(to: .now)
        let seconds = max(0.2, Double(elapsed.components.seconds) +
                          Double(elapsed.components.attoseconds) / 1e18)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("green-\(id.uuidString).mov")
        let videoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("green-video-\(id.uuidString).mov")
        defer { try? FileManager.default.removeItem(at: videoURL) }
        do {
            #if DEBUG
            try await writeDemoVideo(position: previewPosition, to: videoURL, duration: seconds)
            #else
            try await writeVideo(to: videoURL, duration: seconds)
            #endif
            if recorder != nil {
                try await combine(video: videoURL, audio: audioURL, output: url)
            } else {
                try FileManager.default.moveItem(at: videoURL, to: url)
            }
            try Task.checkCancellation()
            guard recordingID == id else { throw CancellationError() }
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func stopVideoRecording() { stopRequested = true }

    private func stopAudioRecording(_ recorder: AVAudioRecorder?) {
        recorder?.stop()
        if audioRecorder === recorder { audioRecorder = nil }
    }

    private func waitForRecording(id: UUID, started: ContinuousClock.Instant) async throws {
        #if DEBUG
        let waitsForManualStop = await MainActor.run {
            RecordingDemoVideoPreview.capturePosition()?.url.lastPathComponent.uppercased()
                == "W04_DOUBLE_FIST.MP4"
        }
        #else
        let waitsForManualStop = false
        #endif
        while recordingID == id && !stopRequested &&
                (waitsForManualStop ||
                 started.duration(to: .now) < .seconds(VideoRecordingSettings.durationSeconds)) {
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
        guard recordingID == id else { throw CancellationError() }
    }

    func cancelVideoRecording() {
        audioRecorder?.stop()
        recordingID = nil
        stopRequested = true
    }

    private func startDemoAudioRecording(at url: URL) throws -> AVAudioRecorder? {
        #if DEBUG
        return try? startAudioRecording(at: url)
        #else
        return try startAudioRecording(at: url)
        #endif
    }

    private func startAudioRecording(at url: URL) throws -> AVAudioRecorder {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .videoRecording,
                                     options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audioSession.setActive(true)
        let recorder = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000
        ])
        guard recorder.record() else { throw CameraSessionError.microphoneUnavailable }
        return recorder
    }
    private func writeVideo(to url: URL, duration: Double) async throws {
        let size = CGSize(width: 720, height: 1280)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        defer {
            if writer.status == .writing { writer.cancelWriting() }
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ])
        guard writer.canAdd(input) else { throw CameraSessionError.cameraUnavailable }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? CameraSessionError.cameraUnavailable
        }
        writer.startSession(atSourceTime: .zero)
        let buffer = try makeGreenBuffer(size: size)
        for time in [0.0, max(0.1, duration - 1.0 / 30.0)] {
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing else {
                    throw writer.error ?? CameraSessionError.cameraUnavailable
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            let presentationTime = CMTime(seconds: time, preferredTimescale: 600)
            guard adaptor.append(buffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? CameraSessionError.cameraUnavailable
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 600))
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? CameraSessionError.cameraUnavailable
        }
    }

    private func makeGreenBuffer(size: CGSize) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                                         kCVPixelFormatType_32BGRA, nil, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            throw CameraSessionError.cameraUnavailable
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let address = CVPixelBufferGetBaseAddress(buffer) {
            let bytes = address.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for row in 0..<Int(size.height) {
                for column in 0..<Int(size.width) {
                    let offset = row * stride + column * 4
                    bytes[offset] = 0
                    bytes[offset + 1] = 255
                    bytes[offset + 2] = 0
                    bytes[offset + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    private func combine(video: URL, audio: URL, output: URL) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        guard let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let sourceAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CameraSessionError.microphoneUnavailable
        }
        let videoDuration = try await videoAsset.load(.duration)
        let audioDuration = try await audioAsset.load(.duration)
        let videoRange = CMTimeRange(start: .zero, duration: videoDuration)
        let audioRange = CMTimeRange(start: .zero, duration: min(audioDuration, videoDuration))
        try videoTrack.insertTimeRange(videoRange, of: sourceVideo, at: .zero)
        try audioTrack.insertTimeRange(audioRange, of: sourceAudio, at: .zero)
        guard let exporter = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw CameraSessionError.cameraUnavailable
        }
        try await exporter.export(to: output, as: .mov)
    }
}

private extension GreenScreenCamera {
    #if DEBUG
    func writeDemoVideo(
        position: RecordingDemoCapturePosition?, to url: URL, duration: Double
    ) async throws {
        if let position {
            try await writePreviewVideo(position: position, to: url, duration: duration)
        } else {
            try await writeVideo(to: url, duration: duration)
        }
    }

    func writePreviewVideo(
        position: RecordingDemoCapturePosition, to url: URL, duration: Double
    ) async throws {
        let asset = AVURLAsset(url: position.url)
        let composition = AVMutableComposition()
        guard let source = try await asset.loadTracks(withMediaType: .video).first,
              let track = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
              ) else { throw CameraSessionError.cameraUnavailable }
        track.preferredTransform = try await source.load(.preferredTransform)
        let assetDuration = try await asset.load(.duration)
        let frame = CMTime(value: 1, timescale: 24)
        let start = min(max(.zero, position.time), max(.zero, assetDuration - frame))
        let wanted = CMTime(seconds: duration, preferredTimescale: 600)
        let available = min(wanted, assetDuration - start)
        try track.insertTimeRange(
            CMTimeRange(start: start, duration: available), of: source, at: .zero
        )
        if available < wanted {
            let lastFrame = CMTimeRange(start: max(.zero, assetDuration - frame), duration: frame)
            try track.insertTimeRange(lastFrame, of: source, at: available)
            track.scaleTimeRange(
                CMTimeRange(start: available, duration: frame), toDuration: wanted - available
            )
        }
        guard let exporter = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality
        ) else { throw CameraSessionError.cameraUnavailable }
        try await exporter.export(to: url, as: .mov)
    }
    #endif

}
#endif
