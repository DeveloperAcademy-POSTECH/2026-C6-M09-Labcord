import Foundation
import LabcordShared
import LabcordWatchOS

@main struct RaceChecks {
  @MainActor static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
      throw NSError(domain: "RaceChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
  }
  @MainActor static func waitFor(_ condition: () -> Bool, _ label: String) async throws {
    for _ in 0..<100000 {
      if condition() { return }
      await Task.yield()
    }
    throw NSError(
      domain: "RaceChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out: \(label)"])
  }
  @MainActor static func main() async throws {
    let service = WatchRecordingService.shared
    let experiment = UUID()
    try await checkStartupCancellation(service, experiment: experiment)
    try await checkStartAndAck(service, experiment: experiment)
    try await checkAckFailureAndLateStart(service, experiment: experiment)
    try await checkStoppedRecorderCancellation(service, experiment: experiment)
    try await checkSavedRecordPreserved(service, experiment: experiment)
  }

  @MainActor static func checkStartupCancellation(
    _ service: WatchRecordingService, experiment: UUID
  ) async throws {
    let first = UUID()
    FakeControl.blockStartup = true
    let firstStart = Task { @MainActor in
      try await service.perform(.startVoice(experimentID: experiment, recordID: first))
    }
    try await waitFor({ FakeControl.startupReached }, "startup")
    let remote = UUID()
    let remoteStart = Task { @MainActor in
      try await service.perform(.startRemoteVoice(
        experimentID: experiment, recordID: remote, expiresAt: .now.addingTimeInterval(0.05)))
    }
    var cancelDispatched = false
    let firstCancel = Task { @MainActor in
      cancelDispatched = true
      try await service.perform(
        .cancelActiveVoiceForPause(experimentID: experiment, recordID: first))
    }
    try await waitFor({ cancelDispatched }, "cancellation dispatch")
    try await Task.sleep(for: .milliseconds(100))
    FakeControl.startupGate?.resume()
    FakeControl.startupGate = nil
    try await firstStart.value
    try await firstCancel.value
    do {
      try await remoteStart.value
      throw NSError(domain: "RaceChecks", code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "expired remote start succeeded"])
    } catch WatchAudioError.interrupted {}
    try require(FakeControl.starts == 0, "expired remote request must not start recording")
    print("PASS: remote request expiry during startup prevents recorder start")
    try require(FakeControl.starts == 0, "cancelled startup must never start recording")
    try require(service.records[first]?.phase == .cancelled, "cancelled startup must settle")
    print("PASS: cancellation before startup completes prevents recording")

  }

  @MainActor static func checkStartAndAck(
    _ service: WatchRecordingService, experiment: UUID
  ) async throws {
    FakeControl.blockStart = true
    FakeControl.blockCancel = true
    var cancelCompleted = false
    let second = UUID()
    let other = WatchAudioHeader(experimentID: UUID(), recordingID: UUID())
    service.archive.items.append(other)
    let secondStart = Task { @MainActor in
      try await service.perform(.startVoice(experimentID: experiment, recordID: second))
    }
    try await waitFor({ FakeControl.startReached }, "recorder start")
    let secondCancel = Task { @MainActor in
      try await service.perform(
        .cancelActiveVoiceForPause(experimentID: experiment, recordID: second))
      cancelCompleted = true
    }
    try await waitFor({
      guard let header = service.recorder.activeRecording else { return false }
      return service.transfer.isCancellationPending(header)
    }, "cancellation registration")
    try require(FakeControl.cancels.isEmpty, "must wait for start before cancellation")
    FakeControl.startGate?.resume()
    FakeControl.startGate = nil
    try await secondStart.value
    try await waitFor({ FakeControl.cancelReached }, "cancellation ACK")
    try require(!cancelCompleted, "must not complete pause preparation before cancellation ACK")
    FakeControl.cancelGate?.resume()
    FakeControl.cancelGate = nil
    FakeControl.blockCancel = false
    try await secondCancel.value
    try require(FakeControl.stops == 1, "active recording must stop")
    try require(FakeControl.cancels == [second], "only targeted recording must be cancelled")
    try require(service.archive.items.contains(other), "other experiment archive must remain")
    try require(
      service.archive.items.contains { $0.recordingID == second },
      "cancelled original must remain")
    print("PASS: cancellation waits for in-flight start and ACK and preserves archives")

  }

  @MainActor static func checkAckFailureAndLateStart(
    _ service: WatchRecordingService, experiment: UUID
  ) async throws {
    FakeControl.blockStart = false
    FakeControl.failCancel = true
    let third = UUID()
    try await service.perform(.startVoice(experimentID: experiment, recordID: third))
    do {
      try await service.perform(
        .cancelActiveVoiceForPause(experimentID: experiment, recordID: third))
      throw NSError(
        domain: "RaceChecks", code: 3,
        userInfo: [NSLocalizedDescriptionKey: "cancel ACK loss incorrectly succeeded"])
    } catch WatchAudioError.incomplete {}
    try require(
      service.archive.items.contains { $0.recordingID == third },
      "ACK failure must preserve original")
    try require(FakeControl.cancels.last == third, "ACK failure must target active recording")
    print("PASS: cancellation ACK failure propagates and preserves original")

    FakeControl.failCancel = false
    let fourth = UUID()
    let startsBefore = FakeControl.starts
    try await service.perform(
      .cancelActiveVoiceForPause(experimentID: experiment, recordID: fourth))
    try await service.perform(.startVoice(experimentID: experiment, recordID: fourth))
    try require(FakeControl.starts == startsBefore, "late start after cancellation must not start")
    try require(service.records[fourth]?.phase == .cancelled, "late start must remain cancelled")
    print("PASS: late start after cancellation stays cancelled")
  }

  @MainActor static func checkStoppedRecorderCancellation(
    _ service: WatchRecordingService, experiment: UUID
  ) async throws {
    let record = UUID()
    try await service.perform(.startVoice(experimentID: experiment, recordID: record))
    FakeControl.blockStop = true
    let stop = Task { @MainActor in
      try await service.perform(.stopVoice(experimentID: experiment, recordID: record))
    }
    try await waitFor({ FakeControl.stopReached }, "recorder released before stop completes")
    try require(service.recorder.activeRecording == nil, "recorder should already be inactive")
    try await service.perform(
      .cancelActiveVoiceForPause(experimentID: experiment, recordID: record))
    try require(FakeControl.cancels.last == record, "inactive stopping record must be cancelled")
    FakeControl.stopGate?.resume()
    FakeControl.stopGate = nil
    FakeControl.blockStop = false
    try await stop.value
    try require(!service.archive.manifests.contains(record), "cancelled stop must not seal audio")
    try require(
      service.archive.items.contains { $0.recordingID == record }, "original must remain")
    print("PASS: pause cancels a stopping record even after recorder is inactive")
  }

  @MainActor static func checkSavedRecordPreserved(
    _ service: WatchRecordingService, experiment: UUID
  ) async throws {
    let record = UUID()
    service.archive.items.append(WatchAudioHeader(experimentID: experiment, recordingID: record))
    service.archive.saved.insert(record)
    let cancellationCount = FakeControl.cancels.count
    do {
      try await service.perform(
        .cancelActiveVoiceForPause(experimentID: experiment, recordID: record))
      throw NSError(domain: "RaceChecks", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "saved record cancellation succeeded"])
    } catch WatchAudioError.conflict {}
    try require(
      FakeControl.cancels.count == cancellationCount, "saved record must not be cancelled")
    try require(
      service.archive.items.contains { $0.recordingID == record }, "saved original must remain")
    print("PASS: already saved record is not cancelled")
  }
}
