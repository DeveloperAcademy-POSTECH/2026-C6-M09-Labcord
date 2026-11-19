//
//  ExperimentActionButton.swift
//  Researchers
//
//  Created by 정홍섭 on 11/16/26.
//

import LabcordDesignSystem
import LabcordWatchOS
import SwiftUI

struct ExperimentActionButton: View {
    let systemName: String
    let action: () -> Void

    private var buttonHeight: CGFloat {
        WatchScreenMetrics.scaledHeight(39.5)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: buttonHeight)
                .background(
                    Color("General/LiveActivity/Secondary"),
                    in: RoundedRectangle(cornerRadius: .infinity)
                )
        }
        .buttonStyle(PressFeedbackButtonStyle())
    }
}

#Preview {
    ExperimentActionButton(systemName: "microphone") { }
}
