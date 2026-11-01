import SwiftUI

public struct FileTypeIcon: View {
    public enum Kind: String, CaseIterable, Sendable {
        case csv
        case pdf
        case docx
        case xls
    }

    private let kind: Kind
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 24

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public var body: some View {
        Image("file-type-\(kind.rawValue)", bundle: .module)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: width, height: height)
            .accessibilityLabel(Text("\(kind.rawValue.uppercased()) 파일"))
    }
}

#Preview("파일 형식 아이콘") {
    HStack(spacing: 16) {
        ForEach(FileTypeIcon.Kind.allCases, id: \.self) { kind in
            FileTypeIcon(kind)
        }
    }
    .padding()
}
