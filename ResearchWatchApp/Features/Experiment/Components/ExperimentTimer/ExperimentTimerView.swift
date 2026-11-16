//
//  ExperimentTimerView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/17/26.
//

import LabcordShared
import SwiftUI

struct ExperimentTimerView: View {
    let mode: ExperimentMode?

    var body: some View {
        if mode == .procedure {
            ProtocolModeTImerView()
        } else {
            FreeModeTimerView()
        }
    }
}

#Preview("자유모드") {
    ExperimentTimerView(mode: .free)
}
