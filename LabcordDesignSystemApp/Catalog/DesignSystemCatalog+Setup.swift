import LabcordDesignSystem
import SwiftUI

struct DesignSystemSetupPage: View {
    let item: CatalogItem

    @State private var showTimerSetting = false
    @State private var duration: Duration = .seconds(600)
    @State private var draftDuration: Duration = .seconds(600)

    var body: some View {
        DesignSystemCatalogPage(title: item.title, context: item.context) {
            switch item {
            case .protocolUploadButton: uploadCard
            case .accordion: accordionCard
            case .experimentListItem: experimentListCard
            case .protocolTimerRow: timerRowCard
            case .protocolTimerItem: timerItemCard
            case .timerSettingSheet: timerSheetCard
            default: EmptyView()
            }
        }
        .fullScreenCover(isPresented: $showTimerSetting) {
            DesignSystemCatalogSheet(context: item.context) {
                TimerSettingSheet(
                    duration: $draftDuration,
                    onCancel: { showTimerSetting = false },
                    onDelete: {
                        duration = .zero
                        showTimerSetting = false
                    },
                    onConfirm: {
                        duration = draftDuration
                        showTimerSetting = false
                    }
                )
            }
        }
    }

    private var uploadCard: some View {
        DesignSystemCatalogCard("Protocol Upload Button", description: "선택과 비활성 상태의 업로드 버튼") {
            CatalogSetupUploadScenario()
        }
    }

    private var accordionCard: some View {
        DesignSystemCatalogCard("Accordion", description: "분석 대상을 펼치고 추가·제거하는 목록") {
            CatalogSetupAccordionScenario()
        }
    }

    private var experimentListCard: some View {
        DesignSystemCatalogCard("Experiment List Item", description: "실험 목록과 상태") {
            CatalogExperimentListItemScenario()
        }
    }

    private var timerRowCard: some View {
        DesignSystemCatalogCard("Protocol Timer Row", description: "프로토콜의 설정 시간") {
            ProtocolTimerRow(duration, onEdit: openTimer)
                .accessibilityIdentifier("catalog.functional.timerRow")
        }
    }

    private var timerItemCard: some View {
        DesignSystemCatalogCard("Protocol Timer Item", description: "짧은 시간과 긴 시간 표기") {
            CatalogSetupProtocolItemScenario()
        }
    }

    private var timerSheetCard: some View {
        DesignSystemCatalogCard("Timer Setting Sheet", description: "시간을 입력하는 설정 화면") {
            Button("타이머 설정 시트 열기", action: openTimer)
            .buttonStyle(.labcord(.secondary, size: .medium))
        }
    }

    private func openTimer() {
        draftDuration = duration
        showTimerSetting = true
    }
}

#Preview("실험 준비 카탈로그") {
    _ = FontRegistration.register()
    return NavigationStack {
        DesignSystemSetupPage(item: .protocolUploadButton)
    }
}
