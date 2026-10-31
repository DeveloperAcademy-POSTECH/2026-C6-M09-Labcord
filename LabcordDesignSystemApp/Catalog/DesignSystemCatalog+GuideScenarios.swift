import LabcordDesignSystem
import SwiftUI

struct CatalogRunGestureScenario: View {
    @State private var isPortrait = false
    @State private var showsMedia = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GestureGuideItem(layout: isPortrait ? .portrait : .landscape) {
                if showsMedia {
                    Image(
                        "catalog-gesture-\(isPortrait ? "portrait" : "landscape")",
                        bundle: LabcordDesignSystemResources.bundle
                    )
                        .resizable()
                        .scaledToFit()
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("catalog.scenario.gesture.preview")
            Picker("배치", selection: $isPortrait) {
                Text("Landscape").tag(false)
                Text("Portrait").tag(true)
            }
            .accessibilityIdentifier("catalog.scenario.gesture.layout")
            Toggle("제스처 이미지 표시", isOn: $showsMedia)
                .accessibilityIdentifier("catalog.scenario.gesture.showMedia")
        }
    }
}

struct CatalogRunSidePanelScenario: View {
    @State private var isPortrait = true
    @State private var isExpanded = true
    @State private var tab = TimerTabs.Selection.running
    @ScaledMetric(relativeTo: .body) private var panelIconSize: CGFloat = 28
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                ExperimentSidePanel(
                    layout: isPortrait ? .portrait : .landscape, isExpanded: $isExpanded
                ) {
                    VStack(spacing: 12) {
                        TimerTabs(selection: $tab, count: 1)
                        ProtocolTimerItem(value: "5", unit: "분")
                    }
                }
                .frame(
                    width: usesIntrinsicAccessibilitySize ? nil : originalWidth,
                    alignment: .bottomTrailing
                )
                .frame(minWidth: usesIntrinsicAccessibilitySize ? originalWidth : nil,
                       alignment: .bottomTrailing)
                .fixedSize(
                    horizontal: usesIntrinsicAccessibilitySize,
                    vertical: usesIntrinsicAccessibilitySize
                )
                .accessibilityIdentifier(
                    "catalog.sidePanel.\(isPortrait ? "portrait" : "landscape")"
                )
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .fixedSize(horizontal: false, vertical: usesIntrinsicAccessibilitySize)
            .frame(
                height: usesIntrinsicAccessibilitySize ? nil : originalHeight,
                alignment: .bottomTrailing
            )
            .frame(minHeight: usesIntrinsicAccessibilitySize ? originalHeight : nil,
                   alignment: .bottomTrailing)
            Picker("배치", selection: $isPortrait) {
                Text("Portrait").tag(true)
                Text("Landscape").tag(false)
            }
            .accessibilityIdentifier("catalog.scenario.sidePanel.layout")
            Toggle("펼침", isOn: $isExpanded)
                .accessibilityIdentifier("catalog.scenario.sidePanel.expanded")
        }
    }

    private var usesIntrinsicAccessibilitySize: Bool {
        dynamicTypeSize.isAccessibilitySize && isExpanded
    }

    private var originalWidth: CGFloat { isPortrait ? 402 : 400 }

    private var originalHeight: CGFloat {
        isPortrait ? max(398, 366 + panelIconSize + 4) : 402
    }

}
