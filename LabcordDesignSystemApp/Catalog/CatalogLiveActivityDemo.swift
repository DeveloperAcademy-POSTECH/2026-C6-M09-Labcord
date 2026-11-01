import LabcordDesignSystem
import SwiftUI

@MainActor
@Observable
final class CatalogLiveActivityDemo {
    var isPresented = false
    var isExpanded = false
    var state: LiveActivityContent.State = .audioRecording(transcript: "실험 내용을 기록하고 있어요.")
    var placement: LiveActivityPlacement?

    private var transitionTask: Task<Void, Never>?
    var devicePlacement: LiveActivityPlacement? {
        LiveActivityPlacement.forDevice(identifier: Self.modelIdentifier)
    }

    func show(state: LiveActivityContent.State) {
        guard let devicePlacement else { return }
        transitionTask?.cancel()
        self.state = state
        placement = devicePlacement
        isExpanded = false
        isPresented = true
        transitionTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            isExpanded = true
        }
    }

    func dismiss() {
        transitionTask?.cancel()
        isExpanded = false
        transitionTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            isPresented = false
        }
    }

    private static var modelIdentifier: String {
        if let simulator = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulator
        }
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}

extension EnvironmentValues {
    @Entry var catalogLiveActivityDemo: CatalogLiveActivityDemo?
}
