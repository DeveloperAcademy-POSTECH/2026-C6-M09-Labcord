import LabcordDesignSystem
import LabcordShared
import SwiftUI

struct CatalogCheckboxScenario: View {
    @State private var size = ComponentSize.small
    @State private var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("체크박스 선택", isOn: $isSelected)
                .toggleStyle(.labcordCheckbox(size: size))
                .labelsVisibility(.hidden)
                .accessibilityIdentifier("catalog.checkbox.preview")
            Picker("크기", selection: $size) {
                catalogPickerOptions(ComponentSize.allCases)
            }
            .accessibilityIdentifier("catalog.checkbox.size")
            Picker("선택", selection: $isSelected) {
                Text("False").tag(false)
                Text("True").tag(true)
            }
            .accessibilityIdentifier("catalog.checkbox.selected")
        }
    }
}

struct CatalogRadioButtonScenario: View {
    @State private var size = ComponentSize.small
    @State private var selection = 2

    private var isSelected: Binding<Bool> {
        Binding(get: { selection == 1 }, set: { selection = $0 ? 1 : 2 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RadioButton("첫 번째 항목", value: 1, selection: $selection, size: size)
                .labelsVisibility(.hidden)
                .accessibilityIdentifier("catalog.radioButton.preview")
            Picker("크기", selection: $size) {
                catalogPickerOptions(ComponentSize.allCases)
            }
            .accessibilityIdentifier("catalog.radioButton.size")
            Picker("선택", selection: isSelected) {
                Text("False").tag(false)
                Text("True").tag(true)
            }
            .accessibilityIdentifier("catalog.radioButton.selected")
            VStack(alignment: .leading, spacing: 8) {
                RadioButton("첫 번째 항목", value: 1, selection: $selection, size: size)
                    .accessibilityIdentifier("catalog.radioButton.optionOne")
                RadioButton("두 번째 항목", value: 2, selection: $selection, size: size)
                    .accessibilityIdentifier("catalog.radioButton.optionTwo")
            }
        }
    }
}
struct CatalogExperimentListItemScenario: View {
    @State private var isSelected = false
    @State private var showBadge = true
    @State private var showRadioButton = true
    @State private var title = "실험 제목"
    @State private var date = "2026.10.13"
    @State private var status = ExperimentStatus.preparing
    @State private var openCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ExperimentListItem(
                title, date: date, status: status,
                isSelected: $isSelected, showBadge: showBadge, showRadioButton: showRadioButton
            ) { openCount += 1 }
            .accessibilityIdentifier("catalog.motion.experimentStatus")
            Picker("상태", selection: $isSelected) {
                Text("Default").tag(false)
                Text("Selected").tag(true)
            }
            .accessibilityIdentifier("catalog.review.experimentList.state")
            Picker("배지 상태", selection: $status) {
                catalogPickerOptions(
                    [ExperimentStatus.preparing, .inProgress, .paused, .completed]
                )
            }
            .accessibilityIdentifier("catalog.review.experimentStatus")
            CatalogDisclosureGroup("콘텐츠 옵션") {
                Toggle("배지 표시", isOn: $showBadge)
                    .accessibilityIdentifier("catalog.review.experimentList.showBadge")
                Toggle("라디오 버튼 표시", isOn: $showRadioButton)
                    .accessibilityIdentifier("catalog.review.experimentList.showRadio")
                CatalogControlTextProperty(title: "실험 제목", value: $title)
                CatalogControlTextProperty(title: "날짜", value: $date)
            }
            Text("실험 열기 \(openCount)회")
                .typography(Typography.caption1)
                .monospacedDigit()
                .accessibilityIdentifier("catalog.review.experimentList.openCount")
        }
    }
}
