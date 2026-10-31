import LabcordDesignSystem
import SwiftUI

enum CatalogTypography: String, CaseIterable {
    case largeTitle = "Large Title"
    case largeTitleEmphasized = "Large Title Emphasized"
    case title1 = "Title 1"
    case title1Emphasized = "Title 1 Emphasized"
    case title2 = "Title 2"
    case title2Emphasized = "Title 2 Emphasized"
    case title3 = "Title 3"
    case title3SemiBold = "Title 3 SemiBold"
    case headline = "Headline"
    case body = "Body"
    case bodySemiBold = "Body SemiBold"
    case callout = "Callout"
    case calloutSemiBold = "Callout SemiBold"
    case subheadline = "Subheadline"
    case subheadlineSemiBold = "Subheadline SemiBold"
    case footnote = "Footnote"
    case footnoteSemiBold = "Footnote SemiBold"
    case caption1 = "Caption 1"
    case caption1SemiBold = "Caption 1 SemiBold"
    case caption2 = "Caption 2"
    case caption2SemiBold = "Caption 2 SemiBold"

    @MainActor
    var style: TypographyStyle {
        switch self {
        case .largeTitle: Typography.largeTitle
        case .largeTitleEmphasized: Typography.largeTitleEmphasized
        case .title1: Typography.title1
        case .title1Emphasized: Typography.title1Emphasized
        case .title2: Typography.title2
        case .title2Emphasized: Typography.title2Emphasized
        case .title3: Typography.title3
        case .title3SemiBold: Typography.title3SemiBold
        case .headline: Typography.headline
        case .body: Typography.body
        case .bodySemiBold: Typography.bodySemiBold
        case .callout: Typography.callout
        case .calloutSemiBold: Typography.calloutSemiBold
        case .subheadline: Typography.subheadline
        case .subheadlineSemiBold: Typography.subheadlineSemiBold
        case .footnote: Typography.footnote
        case .footnoteSemiBold: Typography.footnoteSemiBold
        case .caption1: Typography.caption1
        case .caption1SemiBold: Typography.caption1SemiBold
        case .caption2: Typography.caption2
        case .caption2SemiBold: Typography.caption2SemiBold
        }
    }
}

struct DesignSystemFoundationPage: View {
    let item: CatalogItem
    @State private var palette = CatalogFoundationPalette.semantic

    private var context: ThemeContext { item.context }

    var body: some View {
        DesignSystemCatalogPage(title: item.title, context: context) {
            if item == .typography { typographyCard }
            if item == .spacing { spacingCard }
            if item == .radius { radiusCard }
            if item == .sizes { sizeCard }
            if item == .effects {
                ForEach(ThemeContext.allCases, id: \.rawValue) { context in
                    CatalogFoundationEffectsCard(context: context)
                }
            }

            if item == .colors {
                Picker("팔레트", selection: $palette) {
                    catalogPickerOptions(CatalogFoundationPalette.allCases, capitalized: false)
                }
                #if !os(watchOS)
                .pickerStyle(.segmented)
                #endif
                .accessibilityIdentifier("foundation.palette.kind")
                if palette == .semantic {
                    ForEach(ThemeContext.allCases, id: \.rawValue) { context in
                        CatalogFoundationColorCard(context: context)
                    }
                } else {
                    CatalogPrimitivePaletteView()
                }
            }
        }
    }

    private var typographyCard: some View {
        DesignSystemCatalogCard(
            "Typography",
            description: "Pretendard iOS의 semantic style"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(CatalogTypography.allCases, id: \.rawValue) { style in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(style.rawValue)
                            .typography(Typography.caption1)
                            .foregroundStyle(.labcord(.labelSecondary))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("실험의 흐름을 기록해요 0123456789")
                            .typography(style.style)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier(
                                "foundation.typography.preview.ios.\(style.rawValue)"
                            )
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("foundation.typography.row.ios.\(style.rawValue)")
                }
            }
        }
    }

    private var layout: LayoutTokens { LabcordTheme(context: context).layout }

    private var spacingCard: some View {
        DesignSystemCatalogCard("Spacing", description: "토큰 간격으로 배치한 두 도형") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach([
                    CatalogMetric("spacing/2", layout.spacing2),
                    CatalogMetric("spacing/4", layout.spacing4),
                    CatalogMetric("spacing/8", layout.spacing8),
                    CatalogMetric("spacing/10", layout.spacing10),
                    CatalogMetric("spacing/12", layout.spacing12),
                    CatalogMetric("spacing/16", layout.spacing16),
                    CatalogMetric("spacing/20", layout.spacing20),
                    CatalogMetric("spacing/24", layout.spacing24),
                    CatalogMetric("spacing/32", layout.spacing32)
                ]) { token in
                    VStack(alignment: .leading, spacing: 8) {
                        CatalogMetricLabel(name: token.name, value: token.value)
                        HStack(spacing: token.value) {
                            Rectangle().fill(.labcord(.labelBrand)).frame(width: 20, height: 20)
                            Rectangle().fill(.labcord(.labelBrand)).frame(width: 20, height: 20)
                        }
                        .accessibilityHidden(true)
                    }
                }
            }
        }
        .accessibilityIdentifier("foundation.card.spacing")
    }

    private var radiusCard: some View {
        DesignSystemCatalogCard("Radius", description: "같은 도형에 적용한 모서리 반경") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach([
                    CatalogMetric("radius/sm", layout.radiusSm),
                    CatalogMetric("radius/md", layout.radiusMd),
                    CatalogMetric("radius/lg", layout.radiusLg),
                    CatalogMetric("radius/full", layout.radiusFull)
                ]) { token in
                    VStack(alignment: .leading, spacing: 8) {
                        CatalogMetricLabel(name: token.name, value: token.value)
                        RoundedRectangle(cornerRadius: token.value, style: .continuous)
                            .fill(.labcord(.fillPrimary))
                            .frame(height: 60)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .accessibilityIdentifier("foundation.card.radius")
    }

    private var sizeCard: some View {
        DesignSystemCatalogCard("Size", description: "토큰 크기를 보여주는 도형") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach([
                    CatalogMetric("size/icon/default", layout.iconDefaultSize),
                    CatalogMetric("size/icon/large", layout.iconLargeSize),
                    CatalogMetric("size/control/default", layout.controlDefaultSize),
                    CatalogMetric("size/timer-tab/height", layout.timerTabHeight),
                    CatalogMetric("size/timer-item/height", layout.timerItemHeight)
                ]) { token in
                    VStack(alignment: .leading, spacing: 8) {
                        CatalogMetricLabel(name: token.name, value: token.value)
                        RoundedRectangle(cornerRadius: layout.radiusSm, style: .continuous)
                            .fill(.labcord(.labelBrand))
                            .frame(width: token.value, height: token.value)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .accessibilityIdentifier("foundation.card.size")
    }

}

private struct CatalogMetric: Identifiable {
    let name: String
    let value: CGFloat

    var id: String { name }

    init(_ name: String, _ value: CGFloat) {
        self.name = name
        self.value = value
    }
}

private struct CatalogMetricLabel: View {
    let name: String
    let value: CGFloat

    var body: some View {
        Text("\(name) · \(Double(value).formatted(.number.precision(.fractionLength(0)))) pt")
            .typography(Typography.subheadline)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("foundation.metric.\(name)")
    }
}

private enum CatalogFoundationPalette: String, CaseIterable {
    case semantic = "Semantic"
    case primitive = "Primitive"
}

private struct CatalogFoundationColorCard: View {
    let context: ThemeContext

    var body: some View {
        DesignSystemCatalogCard(context == .general ? "General" : "Experiment") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ColorToken.allCases, id: \.rawValue) { token in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.labcord(token))
                            .frame(width: 52, height: 36)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(.labcord(.borderDefault))
                            }
                            .labcordTheme(LabcordTheme(context: context))
                        Text(token.rawValue)
                            .typography(Typography.subheadline)
                    }
                }
            }
        }
    }
}

private struct CatalogFoundationEffectsCard: View {
    let context: ThemeContext

    private var layout: LayoutTokens { LabcordTheme(context: context).layout }
    private var effects: EffectTokens { LabcordTheme(context: context).effects }

    private var blurMetrics: [CatalogMetric] {
        [
            CatalogMetric("Effect/Blur/Soft/Radius", effects.blurSoftRadius),
            CatalogMetric("Effect/Blur/Medium/Radius", effects.blurMediumRadius),
            CatalogMetric("Effect/Blur/Strong/Radius", effects.blurStrongRadius)
        ]
    }

    private var shadowMetrics: [CatalogMetric] {
        [
            CatalogMetric("Effect/Shadow/Soft/Radius", effects.shadowSoftRadius),
            CatalogMetric("Effect/Shadow/Soft/OffsetY", effects.shadowSoftOffsetY),
            CatalogMetric("Effect/Shadow/Soft/Spread", effects.shadowSoftSpread),
            CatalogMetric("Effect/Shadow/Medium/Radius", effects.shadowMediumRadius),
            CatalogMetric("Effect/Shadow/Medium/OffsetY", effects.shadowMediumOffsetY),
            CatalogMetric("Effect/Shadow/Medium/Spread", effects.shadowMediumSpread),
            CatalogMetric("Effect/Shadow/Strong/Radius", effects.shadowStrongRadius),
            CatalogMetric("Effect/Shadow/Strong/OffsetY", effects.shadowStrongOffsetY),
            CatalogMetric("Effect/Shadow/Strong/Spread", effects.shadowStrongSpread)
        ]
    }

    var body: some View {
        DesignSystemCatalogCard(
            context == .general ? "General · Effect" : "Experiment · Effect",
            description: "현재 맥락의 수치와 native SwiftUI 예시. 원본 background blur와 콘텐츠 blur는 표현 방식이 다릅니다."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(blurMetrics + shadowMetrics) { token in
                    CatalogMetricLabel(name: token.name, value: token.value)
                }

                ForEach(blurMetrics) { token in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("콘텐츠 blur · \(token.name)")
                            .typography(Typography.caption1)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Aa")
                            .typography(Typography.title3)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(
                                .labcord(.fillPrimary),
                                in: RoundedRectangle(cornerRadius: layout.radiusMd)
                            )
                            .foregroundStyle(.labcord(.labelPrimary))
                            .labcordTheme(LabcordTheme(context: context))
                            .blur(radius: token.value)
                            .padding(48)
                            .accessibilityHidden(true)
                    }
                }

                shadowPreview(
                    "Shadow Soft", radius: effects.shadowSoftRadius,
                    offsetY: effects.shadowSoftOffsetY, color: .effectShadowSoftColor
                )
                shadowPreview(
                    "Shadow Medium", radius: effects.shadowMediumRadius,
                    offsetY: effects.shadowMediumOffsetY, color: .effectShadowMediumColor
                )
                shadowPreview(
                    "Shadow Strong", radius: effects.shadowStrongRadius,
                    offsetY: effects.shadowStrongOffsetY, color: .effectShadowStrongColor
                )
            }
        }
        .accessibilityIdentifier("foundation.card.effect")
    }

    private func shadowPreview(
        _ title: String,
        radius: CGFloat,
        offsetY: CGFloat,
        color: ColorToken
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .typography(Typography.caption1)
            Text("Aa")
                .typography(Typography.title3)
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(
                    .labcord(.backgroundPrimary),
                    in: RoundedRectangle(cornerRadius: layout.radiusMd)
                )
                .foregroundStyle(.labcord(.labelPrimary))
                .labcordTheme(LabcordTheme(context: context))
                .shadow(
                    color: LabcordTheme(context: context).color(color),
                    radius: radius, x: 0, y: offsetY
                )
                .padding(radius)
                .accessibilityHidden(true)
        }
    }
}
