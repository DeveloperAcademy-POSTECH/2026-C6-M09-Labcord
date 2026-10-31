import Foundation
import SwiftUI

public struct TimePicker: View {
    @Binding private var hours: Int
    @Binding private var minutes: Int
    @Binding private var seconds: Int

    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    public init(hours: Binding<Int>, minutes: Binding<Int>, seconds: Binding<Int>) {
        _hours = hours
        _minutes = minutes
        _seconds = seconds
    }

    public init(duration: Binding<Duration>) {
        self.init(
            hours: Self.component(duration, unit: 3_600),
            minutes: Self.component(duration, unit: 60, modulus: 60),
            seconds: Self.component(duration, unit: 1, modulus: 60)
        )
    }

    public var body: some View {
        HStack(spacing: 4) {
            wheel("시간", selection: $hours, count: 24)
            separator
            wheel("분", selection: $minutes, count: 60)
            separator
            wheel("초", selection: $seconds, count: 60)
        }
        .frame(height: 174 * textScale)
        .padding(.bottom, 16)
    }

    private var separator: some View {
        Text(":")
            .typography(Typography.title1)
            .foregroundStyle(Color("Experiment/Label/Primary", bundle: .module))
            .frame(width: 14)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func wheel(_ title: String, selection: Binding<Int>, count: Int) -> some View {
        #if os(iOS)
        TimePickerWheel(title: title, selection: selection, count: count, scale: textScale)
            .frame(maxWidth: .infinity)
            .frame(height: 174 * textScale)
            .clipShape(RoundedRectangle(cornerRadius: 22))
        #else
        Picker(title, selection: selection) {
            ForEach(0..<count, id: \.self) { value in
                Text(String(format: "%02d", value)).tag(value)
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text(title))
        #endif
    }

    private static func component(
        _ duration: Binding<Duration>, unit: Int64, modulus: Int64? = nil
    ) -> Binding<Int> {
        let read: @Sendable (Int64) -> Int64 = { seconds in
            let value = seconds / unit
            return modulus.map { value % $0 } ?? value
        }
        return Binding(
            get: { Int(read(duration.wrappedValue.components.seconds)) },
            set: { value, transaction in
                let seconds = duration.wrappedValue.components.seconds
                let updated = seconds + (Int64(value) - read(seconds)) * unit
                duration.transaction(transaction).wrappedValue = .seconds(updated)
            }
        ).transaction(duration.transaction)
    }
}

#Preview("시간 선택") {
    @Previewable @State var duration: Duration = .seconds(3_720)

    _ = FontRegistration.register()
    return TimePicker(duration: $duration)
        .padding()
        .background(Color("Experiment/Background/Primary", bundle: .module))
}
