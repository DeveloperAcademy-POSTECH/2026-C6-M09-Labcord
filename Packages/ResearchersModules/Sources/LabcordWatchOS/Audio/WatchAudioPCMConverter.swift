import AVFoundation
import Foundation
import LabcordShared

final class WatchAudioPCMConverter {
    static let sampleRate = 16_000

    private let converter: AVAudioConverter
    private let inputBuffer: AVAudioPCMBuffer
    private let outputBuffer: AVAudioPCMBuffer

    init(inputSampleRate: Double) throws {
        guard inputSampleRate.isFinite, inputSampleRate > 0,
              let inputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: inputSampleRate,
                channels: 1, interleaved: false
              ), let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: Double(Self.sampleRate),
                channels: 1, interleaved: false
              ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4_096),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4_096)
        else { throw WatchAudioError.invalidAudio }

        self.converter = converter
        self.inputBuffer = inputBuffer
        self.outputBuffer = outputBuffer
    }

    func append(_ data: Data) throws -> Data {
        try convert(data, finishing: false)
    }

    func finish() throws -> Data {
        try convert(Data(), finishing: true)
    }

    private func convert(_ source: Data, finishing: Bool) throws -> Data {
        let inputFrameSize = MemoryLayout<Float>.stride
        guard source.count.isMultiple(of: inputFrameSize),
              let inputSamples = inputBuffer.floatChannelData?[0],
              let outputSamples = outputBuffer.int16ChannelData?[0] else {
            throw WatchAudioError.invalidAudio
        }
        var offset = source.startIndex
        var pcm = Data()
        while true {
            outputBuffer.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { packets, state in
                let frameCount = min(
                    Int(packets), Int(self.inputBuffer.frameCapacity),
                    (source.endIndex - offset) / inputFrameSize
                )
                guard frameCount > 0 else {
                    state.pointee = finishing ? .endOfStream : .noDataNow
                    return nil
                }
                self.inputBuffer.frameLength = AVAudioFrameCount(frameCount)
                let byteCount = frameCount * inputFrameSize
                source.copyBytes(
                    to: UnsafeMutableRawBufferPointer(start: inputSamples, count: byteCount),
                    from: offset..<(offset + byteCount)
                )
                for index in 0..<frameCount where !inputSamples[index].isFinite {
                    inputSamples[index] = 0
                }
                offset += byteCount
                state.pointee = .haveData
                return self.inputBuffer
            }
            guard status != .error, error == nil else { throw WatchAudioError.invalidAudio }
            let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.stride
            pcm.append(contentsOf: UnsafeRawBufferPointer(
                start: outputSamples, count: byteCount
            ))
            switch status {
            case .haveData where outputBuffer.frameLength > 0:
                continue
            case .inputRanDry where !finishing && offset == source.endIndex,
                 .endOfStream where finishing:
                return pcm
            default:
                throw WatchAudioError.invalidAudio
            }
        }
    }
}
