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

#Preview("구분선") {
    VStack(spacing: 16) {
        Text("가로")
        LabcordSeparator()
        HStack {
            Text("세로")
            LabcordSeparator(orientation: .vertical)
            Text("구분")
        }
        .frame(height: 32)
    }
    .padding()
}
