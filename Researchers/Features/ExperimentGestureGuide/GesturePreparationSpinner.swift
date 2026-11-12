import LabcordDesignSystem
import SwiftUI

struct GesturePreparationSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: reduceMotion)) { context in
            let phase = reduceMotion ? 0
                : Int(context.date.timeIntervalSinceReferenceDate * 10) % 8
            ZStack {
                ForEach(0..<8) { index in
                    Capsule()
                        .fill(Color("Experiment/Label/Brand"))
                        .frame(width: 5.33, height: 13.33)
                        .offset(y: -13.33)
                        .rotationEffect(.degrees(Double(index) * 45))
                        .opacity(1 - Double((index - phase + 8) % 8) * 0.12)
                }
            }
            .frame(width: 40, height: 40)
            .accessibilityLabel("준비 중")
        }
    }
}
