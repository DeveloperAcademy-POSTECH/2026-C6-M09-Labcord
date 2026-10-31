import SwiftUI

public enum SeparatorOrientation: Sendable {
    case horizontal
    case vertical
}

public struct Separator: View {
    private let orientation: SeparatorOrientation

    public init(orientation: SeparatorOrientation = .horizontal) {
        self.orientation = orientation
    }

    public var body: some View {
        Group {
            if orientation == .horizontal {
                Rectangle()
                    .fill(Color("General/Border/Default", bundle: .module))
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)
            } else {
                Rectangle()
                    .fill(Color("General/Border/Default", bundle: .module))
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
        Separator()
        HStack {
            Text("세로")
            Separator(orientation: .vertical)
            Text("구분")
        }
        .frame(height: 32)
    }
    .padding()
}
