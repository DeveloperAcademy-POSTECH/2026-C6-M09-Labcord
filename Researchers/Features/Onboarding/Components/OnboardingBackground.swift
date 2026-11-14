//
//  OnboardingBackground.swift
//  Researchers
//
//  Created by lwc0113 on 11/4/26.
//

import LabcordDesignSystem
import SwiftUI

struct OnboardingBackground: View {
    let showsLabImage: Bool

    var body: some View {
        Color("General/Background/Primary", bundle: LabcordDesignSystemResources.bundle)
            .overlay(alignment: .bottom) {
                if showsLabImage {
                    Image("onboarding_lab")
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1206 / 1755, contentMode: .fit)
                        .clipped()
                }
            }
            .ignoresSafeArea()
    }
}
