import LabcordDesignSystem
import SwiftUI

struct CatalogControlButtonScenario: View {
    let iconOnly: Bool

    @State private var size = ComponentSize.small
    @State private var variant = IOSButtonStyle.Variant.primary
    @State private var state = CatalogControlButtonState.normal
    @State private var isDestructive = false
    @State private var showsIcon = true
    @State private var label: String
    @State private var actionCount = 0

    init(iconOnly: Bool) {
        self.iconOnly = iconOnly
        _label = State(initialValue: iconOnly ? "아이콘 버튼" : "버튼")
    }

    private var identifier: String { "catalog.scenario.\(iconOnly ? "iconButton" : "button")" }
    private var icon: Icon { iconOnly ? .caretLeft : .plus }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                preview
                Spacer(minLength: 0)
            }
            Text("실행 \(actionCount)회")
                .typography(Typography.caption1)
                .monospacedDigit()
                .contentTransition(.numericText())
                .labcordMotion(.state, value: actionCount)
                .accessibilityIdentifier(identifier + ".actionCount")

            Picker("크기", selection: $size) {
                catalogPickerOptions(ComponentSize.allCases)
            }
            .accessibilityIdentifier(identifier + ".size")
            Picker("Appearance", selection: $variant) {
                ForEach(IOSButtonStyle.Variant.allCases, id: \.rawValue) { variant in
                    Text(variant.catalogAppearanceName).tag(variant)
                }
            }
            .accessibilityIdentifier(identifier + ".style")
            Picker("상태", selection: $state) {
                catalogPickerOptions(CatalogControlButtonState.allCases, capitalized: false)
            }
            .accessibilityIdentifier(identifier + ".state")
            Picker("역할", selection: $isDestructive) {
                Text("Default").tag(false)
                Text("Destructive").tag(true)
            }
            .accessibilityIdentifier(identifier + ".tone")
            if !iconOnly {
                CatalogDisclosureGroup("콘텐츠 옵션", identifier: identifier + ".contentOptions") {
                    CatalogControlTextProperty(title: "버튼 제목", value: $label)
                    Toggle("아이콘 표시", isOn: $showsIcon)
                        .accessibilityIdentifier(identifier + ".showIcon")
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        Group {
            if iconOnly {
                Button(role: isDestructive ? .destructive : nil) { actionCount += 1 } label: {
                    Image(labcordIcon: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .accessibilityIdentifier(identifier + ".sourceIcon." + icon.rawValue)
                }
                .buttonStyle(.labcordIcon(variant, size: size, isLoading: state == .loading))
            } else {
                Button(role: isDestructive ? .destructive : nil) { actionCount += 1 } label: {
                    if showsIcon {
                        Label { Text(label) } icon: {
                            Image(labcordIcon: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .accessibilityIdentifier(
                                    identifier + ".sourceIcon." + icon.rawValue
                                )
                        }
                    } else {
                        Text(label)
                    }
                }
                .buttonStyle(.labcord(variant, size: size, isLoading: state == .loading))
            }
        }
        .disabled(state != .normal)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier + ".preview")
    }
}

private extension IOSButtonStyle.Variant {
    var catalogAppearanceName: String {
        switch self {
        case .primary: "Filled"
        case .secondary: "Tinted"
        case .tertiary: "Neutral"
        case .quaternary: "Plain"
        case .accent: "Accent"
        }
    }
}

private enum CatalogControlButtonState: String, CaseIterable {
    case normal = "Default"
    case disabled = "Disabled"
    case loading = "Loading"
}
