import LabcordDesignSystem
import SwiftUI

struct CatalogControlDropdownScenario: View {
    @State private var size = LabcordControlSize.medium
    @State private var state = LabcordDropdownState.filled
    @State private var value = "전체 상태"

    private let states: [LabcordDropdownState] = [.default, .filled, .open, .disabled, .error]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabcordDropdownTrigger(value: value, size: size, state: state) {
                Button("준비") { value = "준비" }
                Button("진행 중") { value = "진행 중" }
                Button("완료") { value = "완료" }
            }
            .accessibilityIdentifier("catalog.scenario.dropdown.preview")
            if state == .open {
                Text("Open은 트리거의 표현 미리보기입니다. 탭하면 기본 메뉴가 실제로 열립니다.")
                    .typography(Typography.caption1)
                    .foregroundStyle(Color("General/Label/Secondary", bundle: catalogBundle))
            }
            Picker("크기", selection: $size) {
                Text("Medium").tag(LabcordControlSize.medium)
                Text("Large").tag(LabcordControlSize.large)
            }
            .accessibilityIdentifier("catalog.scenario.dropdown.size")
            Picker("상태", selection: $state) {
                catalogPickerOptions(states)
            }
            .accessibilityIdentifier("catalog.scenario.dropdown.state")
            CatalogDisclosureGroup(
                "콘텐츠 옵션", identifier: "catalog.scenario.dropdown.contentOptions"
            ) {
                CatalogControlTextProperty(title: "표시 값", value: $value)
            }
        }
    }
}

struct CatalogControlChipScenario: View {
    @State private var size = LabcordControlSize.small
    @State private var visualStyle = LabcordChipVisualStyle.solid
    @State private var emphasis = LabcordChipEmphasis.strong
    @State private var isSelected = true
    @State private var isDisabled = false
    @State private var isVisible = true
    @State private var showsIcon = true
    @State private var isDismissible = true
    @State private var label = "중요"
    private let icon = LabcordIcon.plus

    private var state: Binding<CatalogControlChipState> {
        Binding(
            get: { isDisabled ? .disabled : isSelected ? .selected : .normal },
            set: { value in
                isDisabled = value == .disabled
                if value != .disabled { isSelected = value == .selected }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isVisible {
                LabcordChip(
                    isSelected: $isSelected, label: label, leadingIcon: showsIcon ? icon : nil,
                    size: size, style: visualStyle, emphasis: emphasis,
                    onDismiss: isDismissible ? { isVisible = false } : nil
                )
                .disabled(isDisabled)
                .accessibilityIdentifier("catalog.scenario.chip.preview")
            } else {
                Button("칩 다시 표시") { isVisible = true }
                    .buttonStyle(.labcord(.secondary, size: .small))
                    .accessibilityIdentifier("catalog.scenario.chip.restore")
            }
            Picker("크기", selection: $size) {
                Text("Small").tag(LabcordControlSize.small)
                Text("Large").tag(LabcordControlSize.large)
            }
            .accessibilityIdentifier("catalog.scenario.chip.size")
            Picker("스타일", selection: $visualStyle) {
                Text("Solid").tag(LabcordChipVisualStyle.solid)
                Text("Outline").tag(LabcordChipVisualStyle.outline)
            }
            .accessibilityIdentifier("catalog.scenario.chip.style")
            Picker("강조", selection: $emphasis) {
                Text("Strong").tag(LabcordChipEmphasis.strong)
                Text("Weak").tag(LabcordChipEmphasis.weak)
            }
            .accessibilityIdentifier("catalog.scenario.chip.emphasis")
            Picker("상태", selection: state) {
                catalogPickerOptions(CatalogControlChipState.allCases, capitalized: false)
            }
            .accessibilityIdentifier("catalog.scenario.chip.state")
            CatalogDisclosureGroup("콘텐츠 옵션", identifier: "catalog.scenario.chip.contentOptions") {
                CatalogControlTextProperty(title: "칩 제목", value: $label)
                Toggle("아이콘 표시", isOn: $showsIcon)
                    .accessibilityIdentifier("catalog.scenario.chip.showIcon")
                Toggle("제거 버튼 표시", isOn: $isDismissible)
                    .accessibilityIdentifier("catalog.scenario.chip.dismissible")
            }
        }
    }
}

private enum CatalogControlChipState: String, CaseIterable {
    case normal = "Default"
    case selected = "Selected"
    case disabled = "Disabled"
}

struct CatalogControlOverlayScenario: View {
    @State private var isStrong = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color("General/Fill/Primary", bundle: catalogBundle))
                    .frame(height: 48)
                LabcordOverlay(strength: isStrong ? .strong : .default)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("Overlay")
                    .typography(Typography.subheadline)
            }
            .accessibilityIdentifier("catalog.scenario.overlay.preview")
            Picker("강도", selection: $isStrong) {
                Text("Default").tag(false)
                Text("Strong").tag(true)
            }
            .accessibilityIdentifier("catalog.scenario.overlay.strength")
            fadeExample(edge: .top, title: "Fade · Top")
            fadeExample(edge: .bottom, title: "Fade · Bottom")
        }
    }

    private func fadeExample(edge: VerticalEdge, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .typography(Typography.subheadline)
            Color.white
                .frame(height: 100)
                .overlay { LabcordOverlayFade(edge: edge) }
        }
    }
}
