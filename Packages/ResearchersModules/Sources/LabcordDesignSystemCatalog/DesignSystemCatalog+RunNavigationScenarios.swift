import LabcordDesignSystem
import SwiftUI

struct CatalogRunTabsScenario: View {
    @State private var selection = TimerTabs.Selection.running
    @State private var count = 3
    @State private var showsCount = true
    @State private var style = TimerTabs.Style.plain

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimerTabs(
                selection: $selection,
                count: count,
                showCount: showsCount,
                style: style,
                leftTitle: style == .pill ? "iPhone 제스처" : "세팅된 타이머",
                rightTitle: style == .pill ? "Apple Watch 제스처" : "진행중인 타이머"
            )
            .accessibilityIdentifier("catalog.scenario.timerTabs.preview")
            Picker("스타일", selection: $style) {
                Text("Plain").tag(TimerTabs.Style.plain)
                Text("Pill").tag(TimerTabs.Style.pill)
            }
            .accessibilityIdentifier("catalog.scenario.timerTabs.style")
            Picker("선택 탭", selection: $selection) {
                catalogPickerOptions(TimerTabs.Selection.allCases)
            }
            .accessibilityIdentifier("catalog.scenario.timerTabs.selection")
            if style == .plain {
                Toggle("개수 표시", isOn: $showsCount)
                    .accessibilityIdentifier("catalog.scenario.timerTabs.showCount")
                Stepper("타이머 \(count)개", value: $count, in: 0...99)
                    .accessibilityIdentifier("catalog.scenario.timerTabs.count")
            }
        }
    }
}

struct CatalogRunTabItemScenario: View {
    @State private var isSelected = true
    @State private var title = "선택"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimerTabItem(title: title, isSelected: isSelected) { isSelected.toggle() }
                .accessibilityIdentifier("catalog.scenario.timerTabItem.preview")
            Picker("상태", selection: $isSelected) {
                Text("Default").tag(false)
                Text("Selected").tag(true)
            }
            .accessibilityIdentifier("catalog.scenario.timerTabItem.state")
            CatalogDisclosureGroup("콘텐츠 옵션") {
                CatalogControlTextProperty(title: "탭 제목", value: $title)
            }
        }
    }
}

struct CatalogRunPageControlScenario: View {
    @State private var count = 2
    @State private var selection = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageControl(pageCount: count, selection: $selection)
                .accessibilityIdentifier(
                    count == 2 ? "catalog.pageControl.two" : "catalog.pageControl.three"
                )
            Text("현재 페이지: \(selection) / \(count)")
                .typography(Typography.subheadline)
                .foregroundStyle(Color("Experiment/Label/Secondary", bundle: catalogBundle))
            Picker("페이지 수", selection: $count) {
                Text("2").tag(2)
                Text("3").tag(3)
            }
            .accessibilityIdentifier("catalog.scenario.pageControl.count")
        }
        .onChange(of: count) { _, count in selection = min(selection, count) }
    }
}

struct CatalogRunTitleScenario: View {
    @State private var isHorizontal = true
    @State private var title = "촉매 반응 조건 비교 실험 A"
    @State private var actionCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isHorizontal {
                ScrollView(.horizontal) {
                    preview.frame(minWidth: 749)
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .accessibilityIdentifier("design-system-wide-title")
                Text("좌우로 스크롤해 가로 배치를 확인하세요")
                    .typography(Typography.caption1)
                    .foregroundStyle(Color("Experiment/Label/Tertiary", bundle: catalogBundle))
            } else {
                preview
            }
            Picker("배치", selection: $isHorizontal) {
                Text("Landscape").tag(true)
                Text("Portrait").tag(false)
            }
            .accessibilityIdentifier("catalog.scenario.title.layout")
            CatalogDisclosureGroup("콘텐츠 옵션") {
                CatalogControlTextProperty(title: "실험 제목", value: $title)
            }
            Text("동작 \(actionCount)회")
                .typography(Typography.caption1)
                .monospacedDigit()
        }
    }

    private var preview: some View {
        TitleSection(
            title: title, layout: isHorizontal ? .horizontal : .vertical,
            leading: {
                TimerControlButton(state: .running) { actionCount += 1 }
            },
            trailing: {
                HStack(spacing: 24) {
                    ForEach(RecordButton.Kind.allCases, id: \.rawValue) { kind in
                        RecordButton(type: kind) { actionCount += 1 }
                    }
                }
            }
        )
    }
}
