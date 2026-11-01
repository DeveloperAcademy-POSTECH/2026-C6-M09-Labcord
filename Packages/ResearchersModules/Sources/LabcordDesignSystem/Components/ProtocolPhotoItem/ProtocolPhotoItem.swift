import SwiftUI

public struct ProtocolPhotoItem<Content: View>: View {
    private enum Mode {
        case photo
        case add
    }

    private let mode: Mode
    private let content: Content
    private let isAddDisabled: Bool
    private let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 100
    @ScaledMetric(relativeTo: .body) private var addWidth: CGFloat = 41.5

    public init(onRemove: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.mode = .photo
        self.content = content()
        self.isAddDisabled = false
        self.action = onRemove
    }

    public var body: some View {
        Group {
            switch mode {
            case .photo:
                photo
            case .add:
                add
            }
        }
    }

    private var photo: some View {
        content
            .frame(width: height, height: height)
            .clipped()
            .overlay(alignment: .topTrailing) {
                Button(action: action) {
                    IconArtwork(icon: .xCircle, size: 16)
                }
                .buttonStyle(.labcordIcon(.quaternary, size: .medium))
                .accessibilityLabel(Text("사진 삭제"))
            }
            .clipShape(RoundedRectangle(cornerRadius: LayoutTokens.radiusSm))
            .overlay {
                border
            }
    }

    private var add: some View {
        Button(action: action) {
            IconArtwork(icon: .plus, size: 20)
                .foregroundStyle(
                    isAddDisabled || !isEnabled ? Color(.General.Label.disabled)
                        : Color(.General.Label.secondary)
                )
                .frame(width: addWidth, height: height)
                .background(
                    isAddDisabled || !isEnabled ? Color(.General.Fill.disabled)
                        : Color(.General.Fill.light),
                    in: RoundedRectangle(cornerRadius: LayoutTokens.radiusSm)
                )
                .overlay {
                    border
                }
                .contentShape(RoundedRectangle(cornerRadius: LayoutTokens.radiusSm))
        }
        .buttonStyle(LabcordPlainButtonStyle())
        .disabled(isAddDisabled)
        .accessibilityLabel(Text("사진 추가"))
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: LayoutTokens.radiusSm)
            .strokeBorder(Color(.General.Border.`default`), lineWidth: 0.75)
            .allowsHitTesting(false)
    }
}

public extension ProtocolPhotoItem where Content == EmptyView {
    init(isDisabled: Bool = false, onAdd: @escaping () -> Void) {
        self.mode = .add
        self.content = EmptyView()
        self.isAddDisabled = isDisabled
        self.action = onAdd
    }
}

#Preview("프로토콜 사진") {
    HStack(spacing: 8) {
        ProtocolPhotoItem(onRemove: {}, content: {
            Rectangle().fill(Color.gray)
                .accessibilityLabel(Text("실험 사진"))
        })
        ProtocolPhotoItem { }
        ProtocolPhotoItem(isDisabled: true) { }
    }
    .padding()
}
