import SwiftUI

public struct ExperimentListItem: View {
    private let title: String
    private let date: String
    private let status: LabcordStatusBadge.Status
    private let onSelect: () -> Void
    @Binding private var isSelected: Bool
    private let showBadge: Bool
    private let showRadioButton: Bool

    private let layout = LayoutTokens()

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ title: String,
        date: String,
        status: LabcordStatusBadge.Status,
        isSelected: Binding<Bool>,
        showBadge: Bool = true,
        showRadioButton: Bool = true,
        onSelect: @escaping () -> Void
    ) {
        self.init(
            title: title,
            date: date,
            status: status,
            isSelected: isSelected,
            showBadge: showBadge,
            showRadioButton: showRadioButton,
            onSelect: onSelect
        )
    }

    public init(
        title: String = "실험 제목",
        date: String = "2026.10.13",
        status: LabcordStatusBadge.Status = .ready,
        isSelected: Binding<Bool> = .constant(false),
        showBadge: Bool = true,
        showRadioButton: Bool = true,
        onSelect: @escaping () -> Void = {}
    ) {
        self.title = title
        self.date = date
        self.status = status
        _isSelected = isSelected
        self.showBadge = showBadge
        self.showRadioButton = showRadioButton
        self.onSelect = onSelect
    }

    public var body: some View {
        adaptiveContent
        .padding(layout.spacing8)
        .padding(.bottom, 0.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Rectangle()
                .fill(.labcord(.fillSelected))
                .opacity(isSelected ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isSelected)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.labcord(.borderDefault))
                .frame(height: 0.5)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var adaptiveContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalContent
        } else {
            horizontalContent
        }
    }

    private var horizontalContent: some View {
        HStack(alignment: .center, spacing: layout.spacing8) {
            if showRadioButton { selectionButton }
            titleContent
                .frame(maxWidth: .infinity, alignment: .leading)

            actionContent
        }
    }

    private var verticalContent: some View {
        VStack(alignment: .leading, spacing: layout.spacing8) {
            HStack(alignment: .top, spacing: layout.spacing8) {
                if showRadioButton { selectionButton }
                titleContent
            }

            HStack(alignment: .top, spacing: layout.spacing8) {
                if showBadge { statusBadge }
                Spacer(minLength: 0)
                openButton
            }
        }
    }

    private var titleContent: some View {
        VStack(alignment: .leading, spacing: layout.spacing4) {
            Text(title)
                .typography(Typography.body)
                .foregroundStyle(.labcord(.labelPrimary))
                .contentTransition(.opacity)
                .labcordMotion(.state, value: title)
                .fixedSize(horizontal: false, vertical: true)

            Text(date)
                .typography(Typography.subheadline)
                .foregroundStyle(.labcord(.labelTertiary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionContent: some View {
        HStack(spacing: layout.spacing8) {
            if showBadge { statusBadge }
            openButton
        }
    }

    private var selectionButton: some View {
        LabcordRadioButton(value: true, selection: $isSelected, size: .medium) { EmptyView() }
            .accessibilityLabel(Text("실험 선택"))
            .accessibilityHint(Text(title))
    }

    private var openIconForeground: ColorToken {
        isEnabled ? .labelTertiary : .actionDisabledForeground
    }

    private var openButton: some View {
        Button(action: onSelect) {
            LabcordIconArtwork(icon: .caretRight, size: 16)
                .foregroundStyle(.labcord(openIconForeground))
        }
        .buttonStyle(.labcordIcon(.quaternary, size: .medium))
        .accessibilityLabel(Text("실험 열기"))
    }

    private var statusBadge: some View {
        LabcordStatusBadge(status: status)
    }

}

#if DEBUG
#Preview("실험 목록 · 기본") {
    _ = FontRegistration.register()
    return ExperimentListItem()
        .frame(width: 362)
        .padding()
}

#Preview("실험 목록 · 큰 글자") {
    _ = FontRegistration.register()
    return ExperimentListItem(title: "긴 실험 제목을 표시합니다", date: "2026.10.27")
        .environment(\.dynamicTypeSize, .accessibility3)
        .frame(width: 362)
        .padding()
}

#Preview("실험 목록 · 상태") {
    _ = FontRegistration.register()
    return VStack(spacing: 0) {
        ExperimentListItem(status: .running)
        ExperimentListItem(status: .completed)
    }
    .frame(width: 362)
    .padding()
}
#endif
