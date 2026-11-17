//
//  EndExperimentView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/18/26.
//

import SwiftUI

struct EndExperimentView: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .center) {
            Spacer()

            VStack(spacing: 8) {
                Text("실험 종료")
                    .font(.headline)

                Text("진행 중인\n타이머도 함께 종료돼요.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button("취소", action: onCancel)
        }
        .padding(.horizontal, 9.5)
        .padding(.bottom, 10)
        .background(.black)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
            }
        }
    }
}

#Preview {
    EndExperimentView {}
}
