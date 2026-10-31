import LabcordDesignSystem
import SwiftUI

enum CatalogContext: String, CaseIterable, Sendable {
    case general = "General"
    case experiment = "Experiment"
}

enum CatalogSection: String, CaseIterable, Identifiable, Sendable {
    case foundation

    var id: Self { self }

    var title: String {
        switch self {
        case .foundation: "01 Foundation"
        }
    }

    var description: String {
        switch self {
        case .foundation: "글꼴, 색상, 간격, 모서리, 크기, 효과"
        }
    }

    var context: CatalogContext { .general }

    var items: [CatalogItem] { CatalogItem.allCases.filter { $0.section == self } }
}

enum CatalogItem: String, CaseIterable, Identifiable, Sendable {
    case typography, colors, spacing, radius, sizes, effects

    var id: Self { self }

    var title: String {
        switch self {
        case .typography: "Typography"
        case .colors: "Color Tokens"
        case .spacing: "Spacing"
        case .radius: "Radius"
        case .sizes: "Size"
        case .effects: "Effect"
        }
    }

    var section: CatalogSection { .foundation }

    var context: CatalogContext { section.context }

    var isToken: Bool { true }

    @MainActor @ViewBuilder
    var destination: some View {
        DesignSystemFoundationPage(item: self)
    }
}
