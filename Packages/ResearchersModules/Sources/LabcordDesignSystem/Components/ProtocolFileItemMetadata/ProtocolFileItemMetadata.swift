import SwiftUI

public struct ProtocolFileItemMetadata: View {
    private let title: String
    private let dateText: String
    private let onRemove: () -> Void

    public init(title: String, dateText: String, onRemove: @escaping () -> Void) {
        self.title = title
        self.dateText = dateText
        self.onRemove = onRemove
    }

    public var body: some View {
        HStack(spacing: LayoutTokens.spacing16) {
            LabcordIconArtwork(icon: .folderOpen, size: 24)
                .foregroundStyle(Color(.General.Label.secondary))
            VStack(alignment: .leading, spacing: LayoutTokens.spacing2) {
                Text(title)
                    .typography(Typography.body)
                    .foregroundStyle(Color(.General.Label.primary))
                Text(dateText)
                    .typography(Typography.subheadline)
                    .foregroundStyle(Color(.General.Label.tertiary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onRemove) {
                LabcordIconArtwork(icon: .xCircle, size: 16)
            }
            .buttonStyle(.labcordIcon(.quaternary, size: .medium))
            .accessibilityLabel(Text("프로토콜 삭제"))
        }
        .padding(LayoutTokens.spacing12)
        .background(
            Color(.General.Fill.light),
            in: RoundedRectangle(cornerRadius: LayoutTokens.radiusSm)
        )
        .overlay {
            RoundedRectangle(cornerRadius: LayoutTokens.radiusSm)
                .strokeBorder(Color(.General.Border.`default`), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }
}

#Preview("프로토콜 파일 정보") {
    _ = FontRegistration.register()
    return ProtocolFileItemMetadata(title: "실험 제목", dateText: "2016.10.13") { }
        .frame(width: 370)
        .padding()
}
