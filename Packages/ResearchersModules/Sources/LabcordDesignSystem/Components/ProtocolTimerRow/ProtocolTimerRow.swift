import SwiftUI

public struct ProtocolTimerRow: View {
    private let duration: Duration
    private let onEdit: () -> Void

    public init(_ duration: Duration, onEdit: @escaping () -> Void) {
        self.init(duration: duration, onEdit: onEdit)
    }

    public init(
        duration: Duration = .seconds(600),
        onEdit: @escaping () -> Void = {}
    ) {
        self.duration = duration
        self.onEdit = onEdit
    }

    public var body: some View {
        HStack(spacing: 0) {
            Text(duration, format: .labcordDuration)
                .typography(Typography.body)
                .foregroundStyle(Color(.General.Label.primary))
                .contentTransition(.numericText())
                .labcordMotion(.state, value: duration)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onEdit) {
                LabcordIconArtwork(icon: .pencilSimple, size: 16)
            }
            .buttonStyle(.labcordIcon(.quaternary, size: .medium))
            .accessibilityLabel(Text("타이머 수정"))
        }
        .padding(.leading, LayoutTokens.spacing12)
        .padding(.trailing, LayoutTokens.spacing8)
        .padding(.vertical, LayoutTokens.spacing12)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(
            Color(.General.Fill.primary),
            in: RoundedRectangle(cornerRadius: LayoutTokens.radiusSm)
        )
    }
}

#Preview("프로토콜 타이머 · 기본") {
    _ = FontRegistration.register()
    return ProtocolTimerRow()
        .frame(width: 179)
        .padding()
}

#Preview("프로토콜 타이머 · 큰 글자") {
    _ = FontRegistration.register()
    return ProtocolTimerRow(duration: .seconds(3_661))
        .environment(\.dynamicTypeSize, .accessibility3)
        .frame(width: 179)
        .padding()
}

#Preview("프로토콜 타이머 · 주요 상태") {
    _ = FontRegistration.register()
    return VStack {
        ProtocolTimerRow(duration: .seconds(600))
        ProtocolTimerRow(duration: .seconds(86_399))
    }
    .frame(width: 179)
    .padding()
}
