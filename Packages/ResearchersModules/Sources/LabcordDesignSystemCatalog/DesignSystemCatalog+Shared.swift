import LabcordDesignSystem
import SwiftUI

let catalogBundle = LabcordDesignSystemResources.bundle

struct DesignSystemCatalogPage<Content: View>: View {
    @Environment(\.catalogIsEmbedded) private var isEmbedded

    private let title: String
    private let context: CatalogContext
    private let content: () -> Content

    init(
        title: String,
        context: CatalogContext,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.context = context
        self.content = content
    }

    var body: some View {
        if isEmbedded {
            content()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .labcordEntrance()
            }
            .labcordDismissKeyboardOnTapOutside()
            .navigationTitle(title)
            .foregroundStyle(
                context == .general
                    ? Color("General/Label/Primary", bundle: catalogBundle)
                    : Color("Experiment/Label/Primary", bundle: catalogBundle)
            )
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
}

extension EnvironmentValues {
    @Entry var catalogIsEmbedded = false
}

extension View {
    func catalogNavigationBar(context: CatalogContext) -> some View {
        self
            #if os(iOS)
            .toolbarColorScheme(context == .experiment ? .dark : .light, for: .navigationBar)
            #endif
    }
}

struct DesignSystemCatalogCard<Content: View>: View {
    private let title: String
    private let description: String?
    private let content: () -> Content

    init(
        _ title: String,
        description: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.description = description
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .typography(Typography.headline)

            if let description {
                Text(description)
                    .typography(Typography.subheadline)
                    .opacity(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CatalogChipItem: Identifiable, Hashable {
    let id: Int
    let title: String
}

let catalogChipItems = [
    CatalogChipItem(id: 1, title: "샘플 A"),
    CatalogChipItem(id: 2, title: "샘플 B"),
    CatalogChipItem(id: 3, title: "대조군")
]

func catalogNextCase<Value: CaseIterable & Equatable>(_ value: Value) -> Value {
    let values = Array(Value.allCases)
    guard let index = values.firstIndex(of: value) else { return value }
    return values[(index + 1) % values.count]
}

func catalogPickerOptions<Value: RawRepresentable & Hashable>(
    _ values: [Value], capitalized: Bool = true
) -> some View where Value.RawValue == String {
    ForEach(values, id: \.rawValue) { value in
        Text(capitalized ? value.rawValue.capitalized : value.rawValue).tag(value)
    }
}
