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
        .overlay(alignment: .top) {
            GeometryReader { geometry in
                if liveActivityDemo.isCalibrating,
                   let placement = liveActivityDemo.placement,
                   geometry.size.height > geometry.size.width {
                    Capsule()
                        .stroke(.red, lineWidth: 2)
                        .frame(
                            width: placement.collapsedSize.width,
                            height: placement.collapsedSize.height
                        )
                        .frame(maxWidth: .infinity, alignment: .top)
                        .offset(x: placement.horizontalOffset)
                        .padding(.top, placement.top)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
            .allowsHitTesting(false)
        }
    }
}
