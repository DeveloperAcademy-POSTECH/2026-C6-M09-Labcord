import Foundation
import LabcordShared
import LabcordWatchOS

struct WatchRecordPresentation: Equatable, Identifiable, Sendable {
  enum Kind: Equatable, Sendable { case voice, photo, video }
  enum Phase: Equatable, Sendable { case starting, capturing, saving, failed, cancelled, saved }
  let id: UUID
  let experimentID: UUID
  let kind: Kind
  var revision: UInt64 = 0
  var phase: Phase = .starting
  var canAutoSave = false
  var detail: String?
  var captureRejectedBeforeStart = false
  var canRecapture: Bool { phase == .failed && captureRejectedBeforeStart }
  var isSettled: Bool { phase == .cancelled || phase == .saved }
}
struct WatchRecordingUIBridge: Sendable {
  enum Input: Sendable {
    case startVoice(experimentID: UUID, recordID: UUID)
    case stopVoice(experimentID: UUID, recordID: UUID)
    case retry(experimentID: UUID, recordID: UUID)
    case reconcile
    case stopForExperiment(UUID)
    case cancelActiveVoiceForPause(experimentID: UUID, recordID: UUID?)
  }
  var perform: @Sendable (Input) async throws -> Void
  var updates: @Sendable () async -> AsyncStream<WatchRecordPresentation>
}
extension WatchRecordingService {
  func restoreLocalRecords(recordID: UUID? = nil) async throws {}
  func receiveAudio(_ receipt: WatchAudioReceipt) async {}
  func failed(_ header: WatchAudioHeader, detail: String) {}
  func receiveRecord(_ snapshot: WatchRecordSnapshot, experimentID: UUID) {}
  func capture(_ event: WatchAudioCaptureEvent, experimentID: UUID, recordID: UUID) {}
}
