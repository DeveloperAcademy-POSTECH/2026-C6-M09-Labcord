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
    let currentPage: Int

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                Image(imageName)
                    .resizable()
                    .aspectRatio(402.0 / 597.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .overlay(alignment: .bottom) {
                PageControl(pageCount: 3, selection: .constant(currentPage))
                    .frame(height: 32)
                    .padding(.bottom, 8)
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: LayoutTokens.radiusLg, style: .continuous))
            .shadow(
                color: Color("General/Effect/Shadow/Medium/Color"),
                radius: EffectTokens().shadowMediumRadius,
                y: EffectTokens().shadowMediumOffsetY
            )
    }
}
