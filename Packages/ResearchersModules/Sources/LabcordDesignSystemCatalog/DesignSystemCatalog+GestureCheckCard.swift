import LabcordDesignSystem
import SwiftUI

struct DesignSystemGestureCheckCardPage: View {
    @State private var showsFollowingIcon = true

    var body: some View {
        DesignSystemCatalogPage(title: "Gesture Check Card", context: .experiment) {
            DesignSystemCatalogCard("Gesture Check Card", description: "제스처 인식 결과와 안내 문구") {
                GestureToast(
                    title: "토스트 문구입니다.",
                    subtitle: "토스트 문구입니다.",
                    showsFollowingIcon: showsFollowingIcon
                )
                .frame(maxWidth: 241)
                .accessibilityIdentifier("catalog.gestureToast.preview")
                Toggle("뒤 아이콘 표시", isOn: $showsFollowingIcon)
                    .accessibilityIdentifier("catalog.gestureToast.followingIcon")
            }
        }
    }
}

#Preview("제스처 알림 카탈로그") {
    _ = FontRegistration.register()
    return NavigationStack {
        DesignSystemGestureCheckCardPage()
    }
}
