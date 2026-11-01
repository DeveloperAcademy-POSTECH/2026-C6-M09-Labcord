import LabcordDesignSystem
import SwiftUI

@main
struct LabcordDesignSystemApp: App {
    init() {
        FontRegistration.register()
    }

    var body: some Scene {
        WindowGroup {
            CatalogRootView()
        }
    }
}

private struct CatalogRootView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var liveActivityDemo = CatalogLiveActivityDemo()

    var body: some View {
        NavigationStack {
            DesignSystemCatalog()
        }
        .toolbarVisibility(
            liveActivityDemo.isPresented && liveActivityDemo.placement != nil
                && verticalSizeClass != .compact ? .hidden : .automatic,
            for: .statusBar
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.3),
            value: liveActivityDemo.isPresented
        )
        .environment(\.catalogLiveActivityDemo, liveActivityDemo)
        .liveActivityOverlay(
            placement: liveActivityDemo.placement,
            isPresented: liveActivityDemo.isPresented,
            isExpanded: liveActivityDemo.isExpanded
        ) {
            LiveActivityContent(
                state: liveActivityDemo.state,
                onStop: { liveActivityDemo.dismiss() },
                onRetry: { liveActivityDemo.dismiss() }
            )
        }
    }
}
