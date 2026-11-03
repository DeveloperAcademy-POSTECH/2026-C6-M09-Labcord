import BackgroundTasks
import Foundation
import UIKit

@MainActor
final class ProtocolAnalysisBackgroundScheduler {
    static let shared = ProtocolAnalysisBackgroundScheduler()
    private var registered: Set<String> = []
    private var tasks: [UUID: BGContinuedProcessingTask] = [:]
    private var handlers: [UUID: (
        launch: @Sendable () async -> Void, expire: @Sendable () async -> Void
    )] = [:]

    var isForeground: Bool { UIApplication.shared.applicationState == .active }

    func submit(
        id: UUID,
        launch: @escaping @Sendable () async -> Void,
        expire: @escaping @Sendable () async -> Void
    ) async throws {
        let identifier = identifier(for: id)
        handlers[id] = (launch, expire)
        if !registered.contains(identifier) {
            let accepted = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: identifier, using: nil
            ) { task in
                guard let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                Task { @MainActor in
                    guard let callbacks = self.handlers[id] else {
                        task.setTaskCompleted(success: false)
                        return
                    }
                    self.tasks[id] = task
                    task.expirationHandler = { Task { await callbacks.expire() } }
                    await callbacks.launch()
                }
            }
            guard accepted else { throw CocoaError(.featureUnsupported) }
            registered.insert(identifier)
        }
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier, title: "프로토콜 분석", subtitle: "분석 시작을 기다리고 있어요"
        )
        request.strategy = .queue
        // CPU 경로를 사용합니다. GPU 권한을 서명 없이 요청하지 않습니다.
        try await Task.detached {
            try await BGTaskScheduler.shared.submitTaskRequest(request)
        }.value
    }

    func update(id: UUID, completed: Int64, total: Int64, subtitle: String) {
        guard let task = tasks[id] else { return }
        task.progress.totalUnitCount = total
        task.progress.completedUnitCount = completed
        task.updateTitle("프로토콜 분석", subtitle: subtitle)
    }

    func finish(id: UUID, success: Bool) {
        if let task = tasks.removeValue(forKey: id) {
            task.expirationHandler = nil
            task.setTaskCompleted(success: success)
        }
        handlers[id] = nil
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier(for: id))
    }

    private func identifier(for id: UUID) -> String {
        (Bundle.main.bundleIdentifier ?? "com.researchers.Researchers")
            + ".analysis." + id.uuidString
    }
}
