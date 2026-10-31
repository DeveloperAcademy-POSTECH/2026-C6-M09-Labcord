import SwiftUI

public enum LabcordSeparatorOrientation: Sendable {
    case horizontal
    case vertical
}

public struct LabcordSeparator: View {
    private let orientation: LabcordSeparatorOrientation

    public init(orientation: LabcordSeparatorOrientation = .horizontal) {
        self.orientation = orientation
    }

    public var body: some View {
        Group {
            if orientation == .horizontal {
                Rectangle()
                    .fill(.labcord(.borderDefault))
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)
            } else {
                Rectangle()
                    .fill(.labcord(.borderDefault))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}
