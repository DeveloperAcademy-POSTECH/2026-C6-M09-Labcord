import SwiftUI

public struct ProtocolTimerItem: View {
    public enum Format: String, CaseIterable, Sendable {
        case short
        case long
    }

    private let value: String
    private let unit: String
    private let format: Format
    private let layout = LayoutTokens()

    public init(
        value: String,
        unit: String,
        format: Format = .short
    ) {
        self.value = value
        self.unit = unit
        self.format = format
    }

    public var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Text(value)
                .typography(valueTypography)
                .foregroundStyle(Color("Experiment/Label/Primary", bundle: .module))
                .contentTransition(.numericText())
                .labcordMotion(.state, value: value)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(unit)
                .typography(Typography.footnote)
                .foregroundStyle(Color("Experiment/Label/Tertiary", bundle: .module))
                .contentTransition(.opacity)
                .labcordMotion(.state, value: unit)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(layout.spacing4)
        .frame(minWidth: 90, minHeight: 60)
        .background(Color("Experiment/Fill/Primary", bundle: .module), in: roundedShape)
        .clipShape(roundedShape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(value) \(unit)"))
    }

    private var valueTypography: TypographyStyle {
        switch format {
        case .short:
            Typography.title3
        case .long:
            Typography.body
        }
    }

    private var roundedShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: layout.radiusMd, style: .continuous)
    }
}

#Preview("Short") {
    _ = FontRegistration.register()
    return ProtocolTimerItem(value: "5", unit: "분")
        .padding()
        .background(Color("Experiment/Background/Primary", bundle: .module))
}

#Preview("Long") {
    _ = FontRegistration.register()
    return ProtocolTimerItem(value: "05:03:09", unit: "시간", format: .long)
        .padding()
        .background(Color("Experiment/Background/Primary", bundle: .module))
}
