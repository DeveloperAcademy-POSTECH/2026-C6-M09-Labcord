//
//  VoiceWaveView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/17/26.
//

import SwiftUI
import LabcordDesignSystem

struct VoiceWaveView: View {
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Rectangle()
                .frame(width: 2.77, height: 18)
                .cornerRadius(.infinity)
            
            Rectangle()
                .frame(width: 4, height: 26)
                .cornerRadius(.infinity)
            
            Rectangle()
                .frame(width: 4, height: 40)
                .cornerRadius(.infinity)
            
            Rectangle()
                .frame(width: 4, height: 50)
                .cornerRadius(.infinity)
            
            Rectangle()
                .frame(width: 4, height: 40)
                .cornerRadius(.infinity)
            
            Rectangle()
                .frame(width: 4, height: 26)
                .cornerRadius(.infinity)
            
            Rectangle()
                .frame(width: 2.77, height: 18)
                .cornerRadius(.infinity)
        }
        .foregroundStyle(Color("General/Brand/Primary"))
    }
}

#Preview {
    VoiceWaveView()
}
