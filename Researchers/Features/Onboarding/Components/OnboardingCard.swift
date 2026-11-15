//
//  OnboardingCard.swift
//  Researchers
//
//  Created by lwc0113 on 11/4/26.
//

import LabcordDesignSystem
import SwiftUI

struct OnboardingCard: View {
    let imageName: String

    var body: some View {
        GeometryReader { geometry in
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .clipped()
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: LayoutTokens.radiusLg,
                    topTrailingRadius: LayoutTokens.radiusLg,
                    style: .continuous
                ))
                .shadow(
                    color: Color("General/Effect/Shadow/Medium/Color"),
                    radius: EffectTokens().shadowMediumRadius,
                    y: EffectTokens().shadowMediumOffsetY
                )
        }
    }
}
