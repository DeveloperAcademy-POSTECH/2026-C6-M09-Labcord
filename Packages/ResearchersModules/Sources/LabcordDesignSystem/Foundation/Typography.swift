//
//  Typography.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/23/26.
//

import SwiftUI

@MainActor
public enum Typography {
    public static let largeTitle = TypographyStyle(
        font: .custom("PretendardVariable-Regular", size: 34, relativeTo: .largeTitle),
        lineHeight: .exact(points: 41),
        letterSpacing: 0.4
    )
    public static let largeTitleBold = largeTitle.weight(.bold)

    public static let title1 = TypographyStyle(
        font: .custom("PretendardVariable-Regular", size: 28, relativeTo: .title),
        lineHeight: .exact(points: 34),
        letterSpacing: 0.38
    )
    public static let title1Bold = title1.weight(.bold)

    public static let title2 = TypographyStyle(
        font: .custom("PretendardVariable-Regular", size: 22, relativeTo: .title2),
        lineHeight: .exact(points: 28),
        letterSpacing: -0.26
    )
    public static let title2Bold = title2.weight(.bold)

    public static let title3 = TypographyStyle(
        font: .custom("PretendardVariable-Regular", size: 20, relativeTo: .title3),
        lineHeight: .exact(points: 25),
        letterSpacing: -0.45
    )
    public static let title3Bold = title3.weight(.bold)

    public static let headline = TypographyStyle(
        font: .custom("PretendardVariable-Regular", size: 17, relativeTo: .headline)
            .weight(.semibold),
        lineHeight: .exact(points: 22),
        letterSpacing: -0.43
    )

    public static let body = TypographyStyle(
        font: .custom("PretendardVariable-Regular", size: 17, relativeTo: .body),
        lineHeight: .exact(points: 22),
        letterSpacing: -0.43
    )
    public static let bodyBold = body.weight(.bold)

    public static let callout = TypographyStyle(
        font: .custom("PretendardVariable-Regular", size: 16, relativeTo: .callout),
        lineHeight: .exact(points: 21),
        letterSpacing: -0.31
    )
    public static let calloutBold = callout.weight(.bold)

    public static let subheadline = TypographyStyle(
        font: .custom("PretendardVariable-Regular", size: 15, relativeTo: .subheadline),
        lineHeight: .exact(points: 20),
        letterSpacing: -0.23
    )
    public static let subheadlineBold = subheadline.weight(.bold)

    public static let footnote = TypographyStyle(
        font: .custom("PretendardVariable-Regular", size: 13, relativeTo: .footnote),
        lineHeight: .exact(points: 18),
        letterSpacing: -0.08
    )
    public static let footnoteBold = footnote.weight(.bold)

    public static let caption1 = TypographyStyle(
        font: .custom("PretendardVariable-Regular", size: 12, relativeTo: .caption),
        lineHeight: .exact(points: 16),
        letterSpacing: 0
    )
    public static let caption1Bold = caption1.weight(.bold)

    public static let caption2 = TypographyStyle(
        font: .custom("PretendardVariable-Regular", size: 11, relativeTo: .caption2),
        lineHeight: .exact(points: 13),
        letterSpacing: 0.06
    )
    public static let caption2Bold = caption2.weight(.bold)
}
