import Foundation
import SwiftUI

public struct TimerSettingSheet: View {
    @Binding private var hours: Int
    @Binding private var minutes: Int
    @Binding private var seconds: Int

    private let onCancel: (() -> Void)?
    private let onDelete: () -> Void
    private let onConfirm: () -> Void

    private let tokenLayout = LayoutTokens()
    @Environment(\.isPresented) private var isPresented
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var headerControlScale: CGFloat = 1

    public init(
        hours: Binding<Int>,
        minutes: Binding<Int>,
        seconds: Binding<Int>,
        onCancel: (() -> Void)? = nil,
        onDelete: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        _hours = hours
        _minutes = minutes
        _seconds = seconds
        self.onCancel = onCancel
        self.onDelete = onDelete
        self.onConfirm = onConfirm
    }

    public init(
        duration: Binding<Duration>,
        onCancel: (() -> Void)? = nil,
        onDelete: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.init(
            hours: Self.durationComponent(duration, unit: 3_600),
            minutes: Self.durationComponent(duration, unit: 60, modulus: 60),
            seconds: Self.durationComponent(duration, unit: 1, modulus: 60),
            onCancel: onCancel,
            onDelete: onDelete,
            onConfirm: onConfirm
        )
    }

    public var body: some View {
        VStack(spacing: tokenLayout.spacing16) {
            Capsule()
                .fill(Color("General/Timer/Sheet/Grabber", bundle: .module))
                .frame(width: 36, height: 5)
                .accessibilityHidden(true)

            header

            durationPicker

            HStack(spacing: tokenLayout.spacing16) {
                Button(role: .destructive, action: onDelete) {
                    Text("삭제")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.labcord(.quaternary, size: .large))

                Button(action: onConfirm) {
                    Text("저장")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.labcord(.primary, size: .large))
            }
            .padding(.horizontal, -6)
        }
        .padding(.top, tokenLayout.spacing16)
        .padding(.horizontal, tokenLayout.spacing16)
        .padding(.bottom, isPresented ? 0 : tokenLayout.spacing32)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            Color("General/Background/Grouped/Secondary", bundle: .module),
            ignoresSafeAreaEdges: []
        )
        .clipShape(RoundedRectangle(cornerRadius: isPresented ? 0 : 28))
        .shadow(
            color: isPresented ? .clear : resolvedShadowColor,
            radius: EffectTokens().shadowMediumRadius,
            x: 0,
            y: EffectTokens().shadowMediumOffsetY
        )
    }

    private var resolvedShadowColor: Color {
        Color("General/Effect/Shadow/Medium/Color", bundle: .module)
    }

    private var header: some View {
        HStack {
            Button(action: cancel) {
                LabcordIconArtwork(icon: .x, size: 16)
            }
            .buttonStyle(.labcordIcon(.tertiary, size: .medium))
            .accessibilityLabel(Text("닫기"))

            Text("타이머")
                .typography(Typography.bodySemiBold)
                .foregroundStyle(Color("General/Label/Primary", bundle: .module))
                .frame(maxWidth: .infinity)

            Color.clear
                .frame(width: 34 * headerControlScale, height: 34 * headerControlScale)
                .accessibilityHidden(true)
        }
    }

    private func cancel() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    private static func durationComponent(
        _ duration: Binding<Duration>,
        unit: Int64,
        modulus: Int64? = nil
    ) -> Binding<Int> {
        let component: @Sendable (Int64) -> Int64 = { totalSeconds in
            let value = totalSeconds / unit
            return modulus.map { value % $0 } ?? value
        }

        return Binding(
            get: { Int(component(duration.wrappedValue.components.seconds)) },
            set: { newValue, transaction in
                let totalSeconds = duration.wrappedValue.components.seconds
                let componentDelta = Int64(newValue) - component(totalSeconds)
                let updatedSeconds = totalSeconds + componentDelta * unit
                duration.transaction(transaction).wrappedValue = .seconds(updatedSeconds)
            }
        ).transaction(duration.transaction)
    }

    private var durationPicker: some View {
        TimerPicker(hours: $hours, minutes: $minutes, seconds: $seconds, usage: .setup)
    }
}

#if DEBUG
private struct TimerSettingSheetPreviewContent: View {
    @State private var hours = 0
    @State private var minutes = 0
    @State private var seconds = 30

    var body: some View {
        TimerSettingSheet(
            hours: $hours,
            minutes: $minutes,
            seconds: $seconds,
            onCancel: {},
            onDelete: {},
            onConfirm: {}
        )
    }
}

#Preview("타이머 설정 · 기본") {
    _ = FontRegistration.register()
    return TimerSettingSheetPreviewContent()
        .frame(width: 390)
}

#Preview("타이머 설정 · 큰 글자") {
    _ = FontRegistration.register()
    return TimerSettingSheetPreviewContent()
        .environment(\.dynamicTypeSize, .accessibility3)
        .frame(width: 390)
}

#Preview("타이머 설정 · 주요 상태") {
    _ = FontRegistration.register()
    return TimerSettingSheet(
        hours: .constant(23),
        minutes: .constant(59),
        seconds: .constant(59),
        onCancel: {},
        onDelete: {},
        onConfirm: {}
    )
    .frame(width: 390)
}
#endif
