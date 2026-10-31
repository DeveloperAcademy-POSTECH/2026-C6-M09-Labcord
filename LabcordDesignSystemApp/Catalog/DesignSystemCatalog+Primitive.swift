import LabcordDesignSystem
import SwiftUI

struct CatalogPrimitivePaletteView: View {
    @State private var groupID = "13:868"
    @State private var swatchID = "Mint/50"

    private var group: CatalogPrimitiveGroup {
        CatalogPrimitiveData.groups.first { $0.id == groupID } ?? CatalogPrimitiveData.groups[0]
    }

    private var swatch: CatalogPrimitiveSwatch {
        group.swatches.first { $0.id == swatchID } ?? group.swatches[0]
    }

    private var groupSelection: Binding<String> {
        Binding(
            get: { group.id },
            set: { id in
                guard let next = CatalogPrimitiveData.groups.first(where: { $0.id == id }) else {
                    return
                }
                groupID = next.id
                swatchID = next.swatches[0].id
            }
        )
    }

    var body: some View {
        DesignSystemCatalogCard("Primitive", description: "20개 그룹 · 155개 색상 · Gradient 2개") {
            Picker("색 그룹", selection: groupSelection) {
                ForEach(CatalogPrimitiveData.groups) { group in
                    Text(group.title).tag(group.id)
                }
            }
            #if !os(watchOS)
            .pickerStyle(.menu)
            #endif
            .accessibilityIdentifier("foundation.palette.group")

            Picker("색상", selection: $swatchID) {
                ForEach(group.swatches) { swatch in
                    Text(swatch.label).tag(swatch.id)
                }
            }
            #if !os(watchOS)
            .pickerStyle(.menu)
            #endif
            .accessibilityIdentifier("foundation.palette.swatch")

            CatalogPrimitiveSwatchPreview(swatch: swatch)
                .accessibilityIdentifier("foundation.primitive.preview")
        }
    }
}

private struct CatalogPrimitiveSwatchPreview: View {
    let swatch: CatalogPrimitiveSwatch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let edge = swatch.gradientEdge {
                Rectangle()
                    .fill(Color("General/Background/Primary", bundle: catalogBundle))
                    .overlay { OverlayFade(edge: edge) }
                    .aspectRatio(416.0 / 210.0, contentMode: .fit)
                    .frame(maxWidth: 416)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(white: 209.0 / 255.0, opacity: 0.6))
                    }
                    .accessibilityHidden(true)
                Text(swatch.label)
                    .typography(Typography.title2Bold)
                Text(edge == .top ? "Opaque → Clear · 5 layers" : "Clear → Opaque · 5 layers")
                    .typography(Typography.subheadline)
            } else if let value = CatalogPrimitiveData.colors[swatch.name] {
                UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10)
                    .fill(value.color)
                    .frame(width: 200, height: 150)
                    .overlay {
                        if swatch.hasBorder,
                           let border = CatalogPrimitiveData.colors["Neutral/200"] {
                            UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10)
                                .strokeBorder(border.color)
                        }
                    }
                    .accessibilityHidden(true)
                Text(swatch.label)
                    .typography(Typography.title2Bold)
                Text(value.hex)
                    .typography(Typography.body)
                    .monospacedDigit()
                Text(value.description)
                    .typography(Typography.subheadline)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("로컬 원본에서 색상 값을 찾을 수 없어요.")
                    .typography(Typography.subheadline)
            }
            Text(swatch.name)
                .typography(Typography.caption1)
                .foregroundStyle(Color("General/Label/Secondary", bundle: catalogBundle))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
