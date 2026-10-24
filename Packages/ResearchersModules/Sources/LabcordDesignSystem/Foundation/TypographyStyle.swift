//
//  TypographyStyle.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/23/26.
//

import SwiftUI

public struct TypographyStyle: ViewModifier {
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
            .lineHeight(lineHeight)
            .tracking(letterSpacing)
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
