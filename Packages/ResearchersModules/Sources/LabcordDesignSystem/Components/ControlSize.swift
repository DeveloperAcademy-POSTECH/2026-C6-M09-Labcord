import SwiftUI

public enum LabcordControlSize: String, CaseIterable, Sendable {
    case small
    case medium
    case large

    init(_ controlSize: ControlSize) {
        switch controlSize {
        case .mini, .small:
            self = .small
        case .regular:
            self = .medium
        case .large, .extraLarge:
            self = .large
        @unknown default:
            self = .medium
        }
    }
}
