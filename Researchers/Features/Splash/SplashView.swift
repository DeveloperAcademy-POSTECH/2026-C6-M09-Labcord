//
//  SplashView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/1/26.
//

import LabcordDesignSystem
import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color("General/Brand/Primary")
                .ignoresSafeArea()

            Image("splash")
                .resizable()
                .aspectRatio(1.0205, contentMode: .fit)
                .frame(width: 122.46)
        }
    }
}

#Preview {
    SplashView()
}
