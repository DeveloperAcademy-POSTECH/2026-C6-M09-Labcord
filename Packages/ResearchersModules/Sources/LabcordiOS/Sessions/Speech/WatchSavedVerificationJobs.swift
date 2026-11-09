import Foundation
import LabcordShared

@MainActor
final class WatchSavedVerificationJobs {
    typealias Progress = @Sendable (Int64) -> Void
    typealias Verify = @MainActor (WatchAudioHeader, UUID, @escaping Progress) async throws -> Data

    private struct Job {
        let header: WatchAudioHeader
        let generation: UUID
        var lastContact: ContinuousClock.Instant
        var progress: Int64 = 0
        var result: Data?
        var worker: Task<Void, Never>?
        var lease: Task<Void, Never>?
    }

    private var jobs: [UUID: Job] = [:]
    private let verify: Verify
    private let leaseDuration: Duration
    private let leaseCheckInterval: Duration

    init(
        leaseDuration: Duration = .seconds(15),
        leaseCheckInterval: Duration = .seconds(5),
        verify: @escaping Verify
    ) {
        self.verify = verify
        self.leaseDuration = leaseDuration
        self.leaseCheckInterval = leaseCheckInterval
    }

    func begin(_ header: WatchAudioHeader, challenge: UUID) throws -> Data {
        if let existing = jobs[challenge] {
            guard existing.header == header else { throw WatchAudioError.conflict }
            jobs[challenge]?.lastContact = ContinuousClock().now
        } else {
            guard jobs.count < 16 else { throw WatchAudioError.storageFull }
            let generation = UUID()
            jobs[challenge] = Job(
                header: header, generation: generation, lastContact: ContinuousClock().now
            )
            jobs[challenge]?.worker = Task { [weak self] in
                await self?.run(header, challenge: challenge, generation: generation)
            }
            jobs[challenge]?.lease = Task { [weak self] in
                await self?.monitorLease(challenge, generation: generation)
            }
        }
        return try pending(header, challenge: challenge)
    }

    func result(_ header: WatchAudioHeader, challenge: UUID) throws -> Data {
        guard let job = jobs[challenge], job.header == header else {
            throw WatchAudioError.conflict
        }
        jobs[challenge]?.lastContact = ContinuousClock().now
        if let result = job.result { return result }
        return try pending(header, challenge: challenge)
    }

    private func run(_ header: WatchAudioHeader, challenge: UUID, generation: UUID) async {
        let result: Data
        do {
            result = try await verify(header, challenge) { [weak self] samples in
                Task { @MainActor in
                    guard let self, self.jobs[challenge]?.generation == generation else { return }
                    let previous = self.jobs[challenge]?.progress ?? 0
                    self.jobs[challenge]?.progress = max(previous, samples)
                }
            }
        } catch {
            let failure = (error as? WatchAudioError) ?? .storageFailed
            result = (try? JSONEncoder().encode(WatchAudioReceipt(
                header: header, receivedSequences: [], manifest: nil,
                verificationID: challenge, failure: failure
            ))) ?? Data()
        }
        guard jobs[challenge]?.generation == generation else { return }
        jobs[challenge]?.result = result
    }

    private func monitorLease(_ challenge: UUID, generation: UUID) async {
        while !Task.isCancelled {
            do { try await Task.sleep(for: leaseCheckInterval) } catch { return }
            guard let job = jobs[challenge], job.generation == generation else { return }
            if job.lastContact.duration(to: ContinuousClock().now) >= leaseDuration {
                jobs.removeValue(forKey: challenge)?.worker?.cancel()
                return
            }
        }
    }

    private func pending(_ header: WatchAudioHeader, challenge: UUID) throws -> Data {
        try JSONEncoder().encode(WatchAudioReceipt(
            header: header, receivedSequences: [], manifest: nil, verificationID: challenge,
            verificationProgress: jobs[challenge]?.progress
        ))
    }
}
