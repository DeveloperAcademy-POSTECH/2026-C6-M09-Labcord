import SwiftUI

public struct TypographyStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let font: Font
    private let lineHeight: AttributedString.LineHeight
    private let letterSpacing: CGFloat

    public init(
        font: Font,
        lineHeight: AttributedString.LineHeight,
        letterSpacing: CGFloat
    ) {
        self.font = font
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
    }

    public func body(content: Content) -> some View {
        content
            .font(font)
            .lineHeight(resolvedLineHeight)
            .tracking(letterSpacing)
    }

    private var resolvedLineHeight: AttributedString.LineHeight {
        dynamicTypeSize == .large ? lineHeight : .variable
    }

    public func weight(_ weight: Font.Weight) -> Self {
        Self(
            font: font.weight(weight),
            lineHeight: lineHeight,
            letterSpacing: letterSpacing
        )
    }
}

public extension View {
    func typography(_ style: TypographyStyle) -> some View {
        modifier(style)
    }
}
