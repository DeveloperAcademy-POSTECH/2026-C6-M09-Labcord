import SwiftUI

public struct ProtocolFileItemUploadProgress: View {
    private let filename: String
    private let kind: FileTypeIcon.Kind
    private let onCancel: () -> Void
    @ScaledMetric(relativeTo: .footnote) private var progressSize: CGFloat = 22

    public init(
        filename: String,
        kind: FileTypeIcon.Kind,
        onCancel: @escaping () -> Void
    ) {
        self.filename = filename
        self.kind = kind
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(spacing: LayoutTokens.spacing16) {
            FileTypeIcon(kind)
                .padding(LayoutTokens.spacing4)
                .accessibilityHidden(true)
            Text(filename)
                .typography(Typography.footnote)
                .foregroundStyle(Color(.General.Label.primary))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color(.General.Label.brand))
                .scaleEffect(1.1)
                .frame(width: progressSize, height: progressSize)
                .accessibilityLabel(Text("업로드 중"))
            Button(action: onCancel) {
                LabcordIconArtwork(icon: .xCircle, size: 16)
            }
            .buttonStyle(.labcordIcon(.quaternary, size: .medium))
            .accessibilityLabel(Text("업로드 취소"))
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

#Preview("파일 업로드") {
    ProtocolFileItemUploadProgress(filename: "실험 프로토콜.pdf", kind: .pdf) { }
        .frame(width: 370)
        .padding()
}
