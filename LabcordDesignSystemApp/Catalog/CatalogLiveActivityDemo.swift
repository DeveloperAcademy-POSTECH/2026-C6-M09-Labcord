import LabcordDesignSystem
import SwiftUI

@MainActor
@Observable
final class CatalogLiveActivityDemo {
    var isPresented = false
    var isExpanded = false
    var isCalibrating = false
    var state: LiveActivityContent.State = .audioRecording(transcript: "실험 내용을 기록하고 있어요.")
    var placement: LiveActivityPlacement?

    private var transitionTask: Task<Void, Never>?
    private let storageKey =
        "catalog.liveActivityPlacement." + CatalogLiveActivityDemo.modelIdentifier

    var hasSavedPlacement: Bool {
        savedValues() != nil
    }

    func savedValues() -> [Double]? {
        guard let values = UserDefaults.standard.array(forKey: storageKey) as? [Double],
              Self.isValid(values) else { return nil }
        return values
    }

    func save(_ values: [Double]) {
        guard Self.isValid(values) else { return }
        UserDefaults.standard.set(values, forKey: storageKey)
    }

    func show(_ values: [Double], state: LiveActivityContent.State, expanded: Bool = true) {
        guard Self.isValid(values) else { return }
        transitionTask?.cancel()
        self.state = state
        placement = LiveActivityPlacement(
            top: values[0], horizontalOffset: values[1],
            collapsedSize: CGSize(width: values[2], height: values[3]), expandedWidth: values[4]
        )
        isExpanded = false
        isCalibrating = !expanded
        isPresented = true
        guard expanded else { return }
        transitionTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            isExpanded = true
        }
    }

    func dismiss() {
        transitionTask?.cancel()
        isCalibrating = false
        isExpanded = false
        transitionTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            isPresented = false
        }
    }

    private static func isValid(_ values: [Double]) -> Bool {
        guard values.count == 5, values.allSatisfy(\.isFinite) else { return false }
        return (0...100).contains(values[0]) && (-60...60).contains(values[1])
            && (80...180).contains(values[2]) && (20...60).contains(values[3])
            && (250...420).contains(values[4])
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
