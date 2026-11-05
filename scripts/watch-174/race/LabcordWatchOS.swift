import Foundation
import LabcordShared

@MainActor public enum FakeControl {
  public static var blockStartup = false
  public static var startupReached = false
  public static var startupGate: CheckedContinuation<Void, Never>?
  public static var blockStart = false
  public static var startReached = false
  public static var startGate: CheckedContinuation<Void, Never>?
  public static var starts = 0
  public static var stops = 0
  public static var blockStop = false
  public static var stopReached = false
  public static var stopGate: CheckedContinuation<Void, Never>?
  public static var cancels: [UUID] = []
  public static var failCancel = false
  public static var blockCancel = false
  public static var cancelReached = false
  public static var cancelGate: CheckedContinuation<Void, Never>?
}
public enum WatchAudioCaptureEvent: Sendable { case event }
@MainActor public final class WatchAudioRecorder {
  public var activeRecording: WatchAudioHeader?
  let archive: WatchAudioArchive
  public init(archive: WatchAudioArchive) { self.archive = archive }
  public func recoverInterruptedRecordings() async throws {
    if FakeControl.blockStartup {
      FakeControl.startupReached = true
      await withCheckedContinuation { FakeControl.startupGate = $0 }
    }
  }
  public func start(experimentID: UUID, recordingID: UUID) async throws -> AsyncStream<
    WatchAudioCaptureEvent
  > {
    FakeControl.starts += 1
    let header = WatchAudioHeader(experimentID: experimentID, recordingID: recordingID)
    activeRecording = header
    archive.items.append(header)
    if FakeControl.blockStart {
      FakeControl.startReached = true
      await withCheckedContinuation { FakeControl.startGate = $0 }
    }
    return AsyncStream { _ in }
  }
  public func stop() async {
    FakeControl.stops += 1
    activeRecording = nil
    if FakeControl.blockStop {
      FakeControl.stopReached = true
      await withCheckedContinuation { FakeControl.stopGate = $0 }
    }
  }
  public func stopForExperiment(_ id: UUID) async throws -> [Int] { [] }
}
@MainActor public final class WatchAudioTransferClient {
  var pending: Set<UUID> = []
  public init(
    archive: WatchAudioArchive, exchange: @escaping (Int) async throws -> WatchAudioReceipt
  ) {}
  public func startRecovery() {}
  public func recover() async {}
  public func prepareCancellation(_ header: WatchAudioHeader) {
    pending.insert(header.recordingID)
  }
  public func releaseCancellation(_ header: WatchAudioHeader) {}
  public func isCancellationPending(_ header: WatchAudioHeader) -> Bool {
    pending.contains(header.recordingID)
  }
  public func cancel(_ header: WatchAudioHeader) async throws -> WatchAudioReceipt {
    FakeControl.cancels.append(header.recordingID)
    if FakeControl.blockCancel {
      FakeControl.cancelReached = true
      await withCheckedContinuation { FakeControl.cancelGate = $0 }
    }
    if FakeControl.failCancel { throw WatchAudioError.incomplete }
    pending.remove(header.recordingID)
    return WatchAudioReceipt(header: header)
  }
  public func receipts() -> AsyncStream<WatchAudioReceipt> { AsyncStream { _ in } }
  public func receive(_ receipt: WatchAudioReceipt) async throws {}
}
public final class WatchAudioImmediateExchange {
  public init() {}
  public func send(_ input: Int) async throws -> WatchAudioReceipt {
    throw WatchAudioError.incomplete
  }
}
@MainActor public final class FakeRecords {
  public func stream() -> AsyncStream<WatchRecordSnapshot> { AsyncStream { _ in } }
}
@MainActor public final class WatchConnectivitySession {
  public let records = FakeRecords()
  public init() {}
  public func audioReceipts() -> AsyncStream<WatchAudioReceipt> { AsyncStream { _ in } }
}
