import SwiftUI

public enum ComponentSize: String, CaseIterable, Sendable {
    case small
    case medium
    case large
    case extraLarge

    init(_ controlSize: ControlSize) {
        switch controlSize {
        case .mini, .small:
            self = .small
        case .regular:
            self = .medium
        case .large:
            self = .large
        case .extraLarge:
            self = .extraLarge
        @unknown default:
            self = .medium
        }
    }
}
