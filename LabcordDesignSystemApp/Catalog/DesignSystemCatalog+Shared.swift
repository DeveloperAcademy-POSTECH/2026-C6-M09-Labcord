import LabcordDesignSystem
import SwiftUI
#if os(iOS)
import UIKit
#endif

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
            .background {
                CatalogNavigationAppearance(context: context)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
            #endif
    }
}

#if os(iOS)
private struct CatalogNavigationAppearance: UIViewControllerRepresentable {
    let context: CatalogContext

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.catalogContext = self.context
    }

    final class Controller: UIViewController {
        var catalogContext: CatalogContext = .general
        private var originalStyle: UIUserInterfaceStyle?
        private var originalStandard: UINavigationBarAppearance?
        private var originalScrollEdge: UINavigationBarAppearance?
        private var hadScrollEdge = false

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            applyAppearance()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyAppearance()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard let navigationController, let originalStyle, let originalStandard else { return }
            navigationController.navigationBar.overrideUserInterfaceStyle = originalStyle
            navigationController.navigationBar.standardAppearance = originalStandard
            navigationController.navigationBar.scrollEdgeAppearance = hadScrollEdge
                ? originalScrollEdge : nil
            self.originalStyle = nil
            self.originalStandard = nil
            originalScrollEdge = nil
        }

        func applyAppearance() {
            guard let navigationController else { return }
            let bar = navigationController.navigationBar
            if originalStyle == nil {
                originalStyle = bar.overrideUserInterfaceStyle
                originalStandard = bar.standardAppearance.copy() as? UINavigationBarAppearance
                originalScrollEdge = bar.scrollEdgeAppearance?.copy() as? UINavigationBarAppearance
                hadScrollEdge = bar.scrollEdgeAppearance != nil
            }
            let isExperiment = catalogContext == .experiment
            bar.overrideUserInterfaceStyle = isExperiment ? .dark : .light
            let titleColor = UIColor(
                Color(
                    isExperiment ? "Experiment/Label/Primary" : "General/Label/Primary",
                    bundle: catalogBundle
                )
            )
            guard let standard = bar.standardAppearance.copy() as? UINavigationBarAppearance else {
                return
            }
            standard.titleTextAttributes[.foregroundColor] = titleColor
            standard.largeTitleTextAttributes[.foregroundColor] = titleColor
            bar.standardAppearance = standard
            guard let scrollEdge = (bar.scrollEdgeAppearance ?? standard).copy()
                as? UINavigationBarAppearance else { return }
            scrollEdge.titleTextAttributes[.foregroundColor] = titleColor
            scrollEdge.largeTitleTextAttributes[.foregroundColor] = titleColor
            bar.scrollEdgeAppearance = scrollEdge
        }
    }
}
#endif

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
