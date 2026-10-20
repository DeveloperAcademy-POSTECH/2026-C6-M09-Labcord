//
//  WatchPairingView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/20/26.
//

import SwiftUI

struct WatchPairingView: View {
    var body: some View {
        Spacer()
        
        Text("Apple Watch를\n함께 사용할까요?")
            .multilineTextAlignment(.center)
            .font(.title2.bold())
        
        Text("Apple Watch를 사용하면\n손목 제스처와 음성으로 더 편리하게\n실험 기록을 할 수 있어요.")
            .multilineTextAlignment(.center)
        
        Spacer()
        
        Rectangle()
            .frame(width: 100, height: 100)
        
        Rectangle()
            .frame(width: 200, height: 80)
            .foregroundStyle(.gray)
            .overlay {
                VStack {
                    Text("Apple Watch")
                    
                    HStack {
                        Text("페어링됨")
                        Text("75%")
                    }
                }
            }
        
        Spacer()
        
        Button {
            
        } label: {
            Text("Apple Watch 함께 사용하기")
        }
        .buttonStyle(.borderedProminent)
        
        Button {
            
        } label: {
            Text("iPhone만 사용하기")
        }
    }
}

#Preview {
    WatchPairingView()
}
