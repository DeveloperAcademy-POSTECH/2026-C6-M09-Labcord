import ComposableArchitecture
import Foundation

extension ProtocolAnalysisJobManager: DependencyKey {
    public static let liveValue = shared
    public static let testValue = ProtocolAnalysisJobManager(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("labcord-analysis-tests-" + UUID().uuidString),
        usesSystemScheduler: false
    )
}

public extension DependencyValues {
    var protocolAnalysisJobManager: ProtocolAnalysisJobManager {
        get { self[ProtocolAnalysisJobManager.self] }
        set { self[ProtocolAnalysisJobManager.self] = newValue }
    }
}
