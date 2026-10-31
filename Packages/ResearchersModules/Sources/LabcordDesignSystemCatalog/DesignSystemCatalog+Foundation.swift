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
    case title3Emphasized = "Title 3 Emphasized"
    case headline = "Headline"
    case body = "Body"
    case bodyEmphasized = "Body Emphasized"
    case callout = "Callout"
    case calloutEmphasized = "Callout Emphasized"
    case subheadline = "Subheadline"
    case subheadlineEmphasized = "Subheadline Emphasized"
    case footnote = "Footnote"
    case footnoteEmphasized = "Footnote Emphasized"
    case caption1 = "Caption 1"
    case caption1Emphasized = "Caption 1 Emphasized"
    case caption2 = "Caption 2"
    case caption2Emphasized = "Caption 2 Emphasized"

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
        case .title3Emphasized: Typography.title3Emphasized
        case .headline: Typography.headline
        case .body: Typography.body
        case .bodyEmphasized: Typography.bodyEmphasized
        case .callout: Typography.callout
        case .calloutEmphasized: Typography.calloutEmphasized
        case .subheadline: Typography.subheadline
        case .subheadlineEmphasized: Typography.subheadlineEmphasized
        case .footnote: Typography.footnote
        case .footnoteEmphasized: Typography.footnoteEmphasized
        case .caption1: Typography.caption1
        case .caption1Emphasized: Typography.caption1Emphasized
        case .caption2: Typography.caption2
        case .caption2Emphasized: Typography.caption2Emphasized
        }
    }
}

struct DesignSystemFoundationPage: View {
    let item: CatalogItem
    @State private var palette = CatalogFoundationPalette.semantic
    @State private var typographyPlatform = CatalogTypographyPlatform.current

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
            description: "Pretendard iOS / SF Pro watchOS의 공통 semantic style"
        ) {
            Picker("플랫폼", selection: $typographyPlatform) {
                catalogPickerOptions(CatalogTypographyPlatform.allCases, capitalized: false)
            }
            #if !os(watchOS)
            .pickerStyle(.segmented)
            #endif
            .accessibilityIdentifier("foundation.typography.platform")

            if typographyPlatform == .watch {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(CatalogWatchTypography.allCases, id: \.rawValue) { style in
                        CatalogWatchTypographyPreview(style: style)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier(
                                "foundation.typography.row.watch.\(style.rawValue)"
                            )
                    }
                }
            } else {
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
    }

    private var layout: LayoutTokens { LabcordTheme(context: context).layout }

    private var spacingCard: some View {
        DesignSystemCatalogCard("Spacing", description: "토큰 간격으로 배치한 두 도형") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach([
                    LayoutToken.spacing2, .spacing4, .spacing8, .spacing10, .spacing12,
                    .spacing16, .spacing20, .spacing24, .spacing32
                ], id: \.rawValue) { token in
                    VStack(alignment: .leading, spacing: 8) {
                        CatalogMetricLabel(name: token.rawValue, value: layout[token])
                        HStack(spacing: layout[token]) {
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
                    LayoutToken.radiusSm, .radiusMd, .radiusLg, .radiusFull
                ], id: \.rawValue) { token in
                    VStack(alignment: .leading, spacing: 8) {
                        CatalogMetricLabel(name: token.rawValue, value: layout[token])
                        RoundedRectangle(cornerRadius: layout[token], style: .continuous)
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
                    LayoutToken.iconDefaultSize, .iconLargeSize, .controlDefaultSize,
                    .timerTabHeight, .timerItemHeight
                ], id: \.rawValue) { token in
                    VStack(alignment: .leading, spacing: 8) {
                        CatalogMetricLabel(name: token.rawValue, value: layout[token])
                        RoundedRectangle(cornerRadius: layout.radiusSm, style: .continuous)
                            .fill(.labcord(.labelBrand))
                            .frame(width: layout[token], height: layout[token])
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .accessibilityIdentifier("foundation.card.size")
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

    var body: some View {
        DesignSystemCatalogCard(
            context == .general ? "General · Effect" : "Experiment · Effect",
            description: "현재 맥락의 수치와 native SwiftUI 예시. 원본 background blur와 콘텐츠 blur는 표현 방식이 다릅니다."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(EffectToken.allCases, id: \.rawValue) { token in
                    CatalogMetricLabel(name: token.rawValue, value: effects[token])
                }

                ForEach([
                    EffectToken.blurSoftRadius, .blurMediumRadius, .blurStrongRadius
                ], id: \.rawValue) { token in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("콘텐츠 blur · \(token.rawValue)")
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
                            .blur(radius: effects[token])
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
