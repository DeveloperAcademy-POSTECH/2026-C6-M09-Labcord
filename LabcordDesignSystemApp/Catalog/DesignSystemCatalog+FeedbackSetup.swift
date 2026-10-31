import LabcordDesignSystem
import SwiftUI

struct DesignSystemFeedbackPage: View {
    let item: CatalogItem

    @State private var statusMessage = "3초 후 자동 저장됩니다."

    var body: some View {
        DesignSystemCatalogPage(title: item.title, context: item.context) {
            if item == .toast {
                DesignSystemCatalogCard("Toast", description: "성공과 오류 상황의 안내 메시지") {
                    CatalogFeedbackToastScenario()
                }
            }
            if item == .statusPill {
                DesignSystemCatalogCard("Status Pill", description: "비상호작용 상태 안내") {
                    StatusPill(statusMessage)
                    Button("메시지 바꾸기") {
                        statusMessage = statusMessage == "3초 후 자동 저장됩니다."
                            ? "변경 사항을 저장했어요." : "3초 후 자동 저장됩니다."
                    }
                        .buttonStyle(.labcord(.secondary, size: .small))
                        .accessibilityIdentifier("catalog.motion.statusMessage")
                    CatalogDisclosureGroup("콘텐츠 옵션") {
                        CatalogControlTextProperty(title: "메시지", value: $statusMessage)
                    }
                }
            }
        }
    }

}

#Preview("피드백 카탈로그") {
    _ = FontRegistration.register()
    return NavigationStack {
        DesignSystemFeedbackPage(item: .toast)
    }
}
