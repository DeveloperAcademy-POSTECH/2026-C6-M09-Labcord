import LabcordDesignSystem
import SwiftUI

struct DesignSystemRunPage: View {
    let item: CatalogItem

    var body: some View {
        DesignSystemCatalogPage(title: item.title, context: item.context) {
            switch item {
            case .titleSection: titleSectionCard
            case .timerTabs: timerTabsCard
            case .timerTabItem: timerTabItemCard
            case .pageControl: pageControlCard
            case .timerItem: timerItemCard
            case .timerControlButton: timerControlButtonCard
            case .experimentControlButton: experimentControlButtonCard
            case .recordButton: recordButtonCard
            default: EmptyView()
            }
        }
    }

    private var titleSectionCard: some View {
        DesignSystemCatalogCard("Title Section", description: "가로와 세로 화면에서의 실험 제목과 동작") {
            CatalogRunTitleScenario()
        }
    }

    private var timerTabsCard: some View {
        DesignSystemCatalogCard("Timer Tabs", description: "탭 선택과 개수 표시를 확인") {
            CatalogRunTabsScenario()
        }
    }

    private var timerTabItemCard: some View {
        DesignSystemCatalogCard("Timer Tab Item", description: "기본·선택 상태의 타이머 탭") {
            CatalogRunTabItemScenario()
        }
    }

    private var pageControlCard: some View {
        DesignSystemCatalogCard("Page Control", description: "페이지를 선택하면 점의 색과 크기가 함께 바뀝니다") {
            CatalogRunPageControlScenario()
        }
    }

    private var timerItemCard: some View {
        DesignSystemCatalogCard("Timer Item", description: "시간 형식과 실행·일시 정지·완료 상태") {
            CatalogRunTimerScenario()
        }
    }

    private var timerControlButtonCard: some View {
        DesignSystemCatalogCard("Timer Control Button", description: "타이머 상태와 카메라 화면 축소 시연") {
            CatalogRunTimerControlScenario()
        }
    }

    private var experimentControlButtonCard: some View {
        DesignSystemCatalogCard("Experiment Control Button", description: "아이콘과 비활성 상태의 실험 제어") {
            CatalogRunExperimentControlScenario()
        }
    }

    private var recordButtonCard: some View {
        DesignSystemCatalogCard("Record Button", description: "음성·장면·영상 기록과 비활성화 상태") {
            CatalogRunRecordButtonScenario()
        }
    }

}

#Preview("실험 진행 카탈로그") {
    _ = FontRegistration.register()
    return NavigationStack {
        DesignSystemRunPage(item: .timerItem)
    }
}
