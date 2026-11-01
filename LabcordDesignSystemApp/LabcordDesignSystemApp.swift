import LabcordDesignSystem
import SwiftUI

@main
struct LabcordDesignSystemApp: App {
    @State private var liveActivityDemo = CatalogLiveActivityDemo()

    init() {
        FontRegistration.register()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                DesignSystemCatalog()
            }
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
}
