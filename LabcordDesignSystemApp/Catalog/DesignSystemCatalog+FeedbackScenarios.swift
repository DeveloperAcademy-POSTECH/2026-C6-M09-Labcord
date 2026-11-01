import LabcordDesignSystem
import SwiftUI

struct CatalogFeedbackToastScenario: View {
    @State private var tone = ToastType.success
    @State private var message = "프로토콜을 저장했어요."
    @State private var actionTitle = "다시시도"
    @State private var showsIcon = true
    @State private var showsDismiss = true
    @State private var showsAction = true
    @State private var isVisible = true
    @State private var actionCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isVisible {
                Toast(
                    message, type: tone,
                    showLeadingIcon: showsIcon, actionTitle: actionTitle,
                    onAction: showsAction ? {
                        actionCount += 1
                        message = "프로토콜을 다시 확인했어요."
                    } : nil,
                    onDismiss: showsDismiss ? { isVisible = false } : nil
                )
                .transition(.opacity)
                .accessibilityIdentifier("catalog.scenario.toast.preview")
            } else {
                Button("메시지 다시 보기") { isVisible = true }
                    .buttonStyle(.labcord(.secondary, size: .small))
                    .accessibilityIdentifier("catalog.scenario.toast.restore")
            }
            Picker("알림 종류", selection: $tone) {
                ForEach(ToastType.allCases, id: \.self) { tone in
                    Text(String(describing: tone).capitalized).tag(tone)
                }
            }
            .accessibilityIdentifier("catalog.scenario.toast.tone")
            CatalogDisclosureGroup("콘텐츠 옵션") {
                Toggle("아이콘 표시", isOn: $showsIcon)
                Toggle("닫기 버튼 표시", isOn: $showsDismiss)
                Toggle("액션 버튼 표시", isOn: $showsAction)
                CatalogControlTextProperty(title: "메시지", value: $message)
                CatalogControlTextProperty(title: "액션 제목", value: $actionTitle)
            }
            Text("액션 \(actionCount)회")
                .typography(Typography.caption1)
                .monospacedDigit()
                .accessibilityIdentifier("catalog.scenario.toast.actionCount")
        }
        .labcordMotion(.layout, value: isVisible)
    }
}

struct CatalogSetupAccordionScenario: View {
    @State private var isExpanded = true
    @State private var isDisabled = false
    @State private var showsCount = true
    @State private var title = "샘플·분석 대상"
    @State private var chipItems = catalogChipItems
    @State private var nextChipID = (catalogChipItems.map(\.id).max() ?? 0) + 1

    private var state: Binding<CatalogAccordionScenarioState> {
        Binding(
            get: { isDisabled ? .disabled : isExpanded ? .expanded : .collapsed },
            set: { next in
                isDisabled = next == .disabled
                isExpanded = next == .expanded
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Accordion(
                title, count: chipItems.count,
                showsCount: showsCount, isExpanded: $isExpanded,
                state: isDisabled ? .disabled : .default
            ) {
                ChipGroup(
                    chipItems, label: \.title,
                    onRemove: { item in chipItems.removeAll { $0.id == item.id } },
                    onAdd: {
                        let item = CatalogChipItem(id: nextChipID, title: "샘플 \(nextChipID)")
                        nextChipID += 1
                        chipItems.append(item)
                    }
                )
            }
            .accessibilityIdentifier("catalog.scenario.accordion.preview")
            Picker("상태", selection: state) {
                catalogPickerOptions(CatalogAccordionScenarioState.allCases, capitalized: false)
            }
            .accessibilityIdentifier("catalog.scenario.accordion.state")
            CatalogDisclosureGroup("콘텐츠 옵션") {
                Toggle("개수 표시", isOn: $showsCount)
                    .accessibilityIdentifier("catalog.scenario.accordion.showCount")
                CatalogControlTextProperty(title: "아코디언 제목", value: $title)
            }
        }
    }
}

private enum CatalogAccordionScenarioState: String, CaseIterable {
    case expanded = "Default · Expanded"
    case collapsed = "Default · Collapsed"
    case disabled = "Disabled · Collapsed"
}

struct CatalogSetupUploadScenario: View {
    @State private var state = ProtocolUploadButtonState.selected
    @State private var title = "연구 프로토콜"
    @State private var detail = "PDF와 XLSX 파일을 선택해 주세요"
    @State private var actionCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProtocolUploadButton(title, description: detail, state: state) {
                actionCount += 1
                state = state == .selected ? .default : .selected
            }
            .accessibilityIdentifier("catalog.motion.upload")
            Picker("상태", selection: $state) {
                Text("Default").tag(ProtocolUploadButtonState.default)
                Text("Selected").tag(ProtocolUploadButtonState.selected)
                Text("Disabled").tag(ProtocolUploadButtonState.disabled)
            }
            .accessibilityIdentifier("catalog.scenario.upload.state")
            CatalogDisclosureGroup("콘텐츠 옵션") {
                CatalogControlTextProperty(title: "프로토콜 제목", value: $title)
                CatalogControlTextProperty(title: "설명", value: $detail)
            }
            Text("선택 \(actionCount)회")
                .typography(Typography.caption1)
                .monospacedDigit()
                .accessibilityIdentifier("catalog.scenario.upload.actionCount")
        }
    }
}

struct CatalogSetupProtocolItemScenario: View {
    @State private var format = ProtocolTimerItem.Format.short
    @State private var shortValue = "10"
    @State private var shortUnit = "분"
    @State private var longValue = "2시간 16"
    @State private var longUnit = "분"

    private var value: Binding<String> { format == .short ? $shortValue : $longValue }
    private var unit: Binding<String> { format == .short ? $shortUnit : $longUnit }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProtocolTimerItem(value: value.wrappedValue, unit: unit.wrappedValue, format: format)
                .accessibilityIdentifier("catalog.scenario.protocolItem.preview")
            Picker("형식", selection: $format) {
                catalogPickerOptions(ProtocolTimerItem.Format.allCases)
            }
            .accessibilityIdentifier("catalog.scenario.protocolItem.format")
            CatalogDisclosureGroup("콘텐츠 옵션") {
                CatalogControlTextProperty(title: "시간 값", value: value)
                CatalogControlTextProperty(title: "시간 단위", value: unit)
            }
        }
    }
}
