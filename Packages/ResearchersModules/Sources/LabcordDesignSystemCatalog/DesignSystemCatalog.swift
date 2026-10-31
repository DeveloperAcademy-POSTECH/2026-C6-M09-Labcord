import LabcordDesignSystem
import SwiftUI

public struct DesignSystemCatalog: View {
    public init() {}

    public var body: some View {
        List {
            ForEach(CatalogSection.allCases) { section in
                NavigationLink {
                    DesignSystemCatalogSectionPage(section: section)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .typography(Typography.headline)
                        Text(section.description)
                            .typography(Typography.subheadline)
                            .foregroundStyle(.labcord(.labelSecondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("catalog.section.\(section.rawValue)")
            }
        }
        .catalogList(context: .general)
        .navigationTitle("디자인 시스템")
    }
}

private struct DesignSystemCatalogSectionPage: View {
    let section: CatalogSection

    var body: some View {
        List {
            Section {
                NavigationLink {
                    DesignSystemCatalogAllPage(section: section)
                } label: {
                    Text("All")
                        .typography(Typography.body)
                        .padding(.vertical, 4)
                }
                .accessibilityIdentifier("catalog.all.\(section.rawValue)")
            }

            if section == .foundation {
                Section("Foundation Tokens") {
                    itemLinks(section.items.filter(\.isToken))
                }
                if section.items.contains(where: { !$0.isToken }) {
                    Section("Components") {
                        itemLinks(section.items.filter { !$0.isToken })
                    }
                }
            } else {
                itemLinks(section.items)
            }
        }
        .catalogList(context: section.context)
        .navigationTitle(section.title)
    }

    private func itemLinks(_ items: [CatalogItem]) -> some View {
        ForEach(items) { item in
            NavigationLink {
                item.destination
            } label: {
                Text(item.title)
                    .typography(Typography.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }
            .accessibilityIdentifier("catalog.component.\(item.rawValue)")
        }
    }
}

private struct DesignSystemCatalogAllPage: View {
    let section: CatalogSection

    var body: some View {
        DesignSystemCatalogPage(title: "All", context: section.context) {
            ForEach(section.items) { item in
                item.destination
                    .environment(\.catalogIsEmbedded, true)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("catalog.allItem.\(item.rawValue)")
            }
        }
    }
}

private extension View {
    func catalogList(context: ThemeContext) -> some View {
        self
            .scrollContentBackground(.hidden)
            .foregroundStyle(.labcord(.labelPrimary))
            .labcordEntrance()
            .background {
                Rectangle()
                    .fill(.labcord(.backgroundPrimary))
                    .ignoresSafeArea()
            }
            .labcordTheme(LabcordTheme(context: context))
            .catalogNavigationBar(context: context)
    }
}

#if DEBUG
#Preview("Figma 섹션") {
    _ = FontRegistration.register()
    return NavigationStack {
        DesignSystemCatalog()
    }
}

#Preview("Figma 섹션 · 큰 글자") {
    _ = FontRegistration.register()
    return NavigationStack {
        DesignSystemCatalog()
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
