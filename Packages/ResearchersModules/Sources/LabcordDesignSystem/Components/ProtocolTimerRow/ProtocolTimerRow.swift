import SwiftUI

public struct ProtocolTimerRow: View {
    public enum Rows: Sendable {
        case one
        case two
    }

    private let duration: Duration
    private let rows: Rows
    private let showEditButton: Bool
    private let onEdit: () -> Void

    public init(
        _ duration: Duration, rows: Rows = .one, showEditButton: Bool = true,
        onEdit: @escaping () -> Void
    ) {
        self.init(duration: duration, rows: rows, showEditButton: showEditButton, onEdit: onEdit)
    }

    public init(
        duration: Duration = .seconds(600),
        rows: Rows = .one,
        showEditButton: Bool = true,
        onEdit: @escaping () -> Void = {}
    ) {
        self.duration = duration
        self.rows = rows
        self.showEditButton = showEditButton
        self.onEdit = onEdit
    }

    public var body: some View {
        HStack(spacing: 0) {
            durationContent
                .foregroundStyle(Color(.General.Label.primary))
                .contentTransition(.numericText())
                .labcordMotion(.state, value: duration)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showEditButton {
                Button(action: onEdit) {
                    IconArtwork(icon: .pencilSimple, size: 16)
                }
                .buttonStyle(.labcordIcon(.quaternary, size: .medium))
                .accessibilityLabel(Text("타이머 수정"))
            }
        }
        .padding(LayoutTokens.spacing8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(
            Color(.General.Fill.primary),
            in: RoundedRectangle(cornerRadius: LayoutTokens.radiusSm)
        )
    }

    @ViewBuilder
    private var durationContent: some View {
        let parts = TimerDurationFormatStyle().formattedParts(for: duration)
        switch rows {
        case .one:
            let value = Text(parts.value).foregroundColor(Color(.General.Label.primary))
            let unit = Text(parts.unit).foregroundColor(Color(.General.Label.secondary))
            Text("\(value)\(unit)")
            .typography(Typography.body)
            .accessibilityLabel(Text(parts.text))
        case .two:
            VStack(alignment: .leading, spacing: 0) {
                Text(parts.value)
                Text(parts.unit)
                    .foregroundStyle(Color(.General.Label.secondary))
            }
            .typography(Typography.subheadline)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(parts.text))
        }
    }
}

#Preview("프로토콜 타이머 · 기본") {
    _ = FontRegistration.register()
    return ProtocolTimerRow()
        .frame(width: 120)
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
        ProtocolTimerRow(duration: .seconds(600), rows: .two)
        ProtocolTimerRow(duration: .seconds(86_399))
    }
    .frame(width: 179)
    .padding()
}
