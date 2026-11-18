#if DEBUG
import Foundation
import LabcordShared
import SwiftData

@MainActor
public enum DebugExperimentStorage {
    public static func reset() throws -> [String] {
        let coordinator = PhoneWatchExperimentCoordinator.shared
        try coordinator.checkDebugDataResetAvailability()

        let context = try ExperimentStore.shared.makeContext()
        for experiment in try context.fetch(FetchDescriptor<Experiment>()) {
            context.delete(experiment)
        }
        try context.save()

        coordinator.beginDebugDataReset()
        defer { coordinator.endDebugDataReset() }
        return cleanFiles()
    }

    private static func cleanFiles() -> [String] {
        var cleanup = Cleanup()
        let root = URL.applicationSupportDirectory
        for name in [
            "Photos", "Videos", "Audio", "VoiceRecordingJournals",
            "IncompleteVoiceRecordings", "WatchAudioIncoming",
            "WatchExperiment/requests.json",
            "WatchExperiment/dismissedTimers.json"
        ] {
            cleanup.attempt(name) { try removeIfPresent(root.appending(path: name)) }
        }
        cleanupWatchAudio(in: root.appending(path: "WatchAudioInbox"), using: &cleanup)
        PhoneWatchAudioService.shared.clearDebugData()
        cleanup.attempt("음성 디버그 로그") {
            try removeIfPresent(URL.documentsDirectory.appending(path: "speech-debug.log"))
        }
        cleanup.attempt("음성 언어 모델 캐시") {
            try removeIfPresent(URL.cachesDirectory.appending(path: "SpeechCustomLM"))
        }
        cleanup.attempt("음성 발음 캐시") { try TermStringCache.readings.resetDebugData() }
        removeTemporaryRecords(using: &cleanup)
        return cleanup.failures
    }

    private static func cleanupWatchAudio(in inbox: URL, using cleanup: inout Cleanup) {
        guard FileManager.default.fileExists(atPath: inbox.path) else { return }
        do {
            let entries = try FileManager.default.contentsOfDirectory(
                at: inbox, includingPropertiesForKeys: nil
            )
            for entry in entries where entry.lastPathComponent != "record-revision.txt" {
                cleanup.attempt("Watch 음성 기록") { try removeIfPresent(entry) }
            }
        } catch {
            cleanup.addFailure("Watch 음성 기록")
        }
    }

    private static func removeTemporaryRecords(using cleanup: inout Cleanup) {
        let fileManager = FileManager.default
        do {
            let files = try fileManager.contentsOfDirectory(
                at: fileManager.temporaryDirectory, includingPropertiesForKeys: nil
            )
            let prefixes = ["labcord-protocol-", "voice-recovery-", "labcord-demo-"]
            for file in files {
                let name = file.lastPathComponent
                let isCameraVideo = name.hasPrefix("video-") && file.pathExtension == "mov"
                if isCameraVideo || prefixes.contains(where: { name.hasPrefix($0) }) {
                    cleanup.attempt("임시 기록 파일") { try removeIfPresent(file) }
                }
            }
        } catch {
            cleanup.addFailure("임시 기록 파일")
        }
    }

    private struct Cleanup {
        private(set) var failures: [String] = []

        mutating func attempt(_ category: String, _ operation: () throws -> Void) {
            do {
                try operation()
            } catch {
                addFailure(category)
            }
        }

        mutating func addFailure(_ category: String) {
            if !failures.contains(category) { failures.append(category) }
        }
    }

    private static func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
#endif
