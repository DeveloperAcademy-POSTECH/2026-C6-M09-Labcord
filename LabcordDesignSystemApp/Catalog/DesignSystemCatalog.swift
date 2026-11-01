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
                            .foregroundStyle(
                                Color(.generalLabelSecondary)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    .catalogDisclosure(context: .general)
                }
                .catalogListRow(context: .general)
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
                        .catalogDisclosure(context: section.context)
                }
                .catalogListRow(context: section.context)
                .accessibilityIdentifier("catalog.all.\(section.rawValue)")
            }

            if section == .foundation {
                Section {
                    itemLinks(section.items.filter(\.isToken))
                } header: {
                    sectionHeading("Foundation Tokens")
                }
                if section.items.contains(where: { !$0.isToken }) {
                    Section {
                        itemLinks(section.items.filter { !$0.isToken })
                    } header: {
                        sectionHeading("Components")
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
                    .catalogDisclosure(context: section.context)
            }
            .catalogListRow(context: section.context)
            .accessibilityIdentifier("catalog.component.\(item.rawValue)")
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(Color(.generalLabelSecondary))
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
    func catalogDisclosure(context: CatalogContext) -> some View {
        HStack {
            self
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    Color(
                        context == .general ? .generalLabelSecondary : .experimentLabelSecondary
                    )
                )
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func catalogListRow(context: CatalogContext) -> some View {
        self
            .navigationLinkIndicatorVisibility(.hidden)
            .listRowBackground(
                Color(
                    context == .general
                        ? .generalBackgroundGroupedSecondary
                        : .experimentBackgroundGroupedSecondary
                )
            )
            .listRowSeparatorTint(
                Color(context == .general ? .generalSeparatorDefault : .experimentSeparatorDefault)
            )
    }

    func catalogList(context: CatalogContext) -> some View {
        self
            .scrollContentBackground(.hidden)
            .foregroundStyle(
                context == .general
                    ? Color(.generalLabelPrimary)
                    : Color(.experimentLabelPrimary)
            )
            .labcordEntrance()
            .background {
                Rectangle()
                    .fill(
                        context == .general
                            ? Color("General/Background/Primary", bundle: catalogBundle)
                            : Color("Experiment/Background/Primary", bundle: catalogBundle)
                    )
                    .ignoresSafeArea()
            }

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
