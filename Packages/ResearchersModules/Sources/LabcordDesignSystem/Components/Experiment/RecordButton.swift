import SwiftUI

public struct RecordButton: View {
    public enum Kind: String, CaseIterable, Sendable {
        case audio
        case capture
        case video

        fileprivate var icon: LabcordIcon {
            switch self {
            case .audio:
                .record
            case .capture:
                .capture
            case .video:
                .videocameraFill
            }
        }

        fileprivate var accessibilityLabel: String {
            switch self {
            case .audio:
                "음성 기록"
            case .capture:
                "장면 캡처"
            case .video:
                "영상 기록"
            }
        }
    }

    public enum State: String, CaseIterable, Sendable {
        case `default`
        case disabled
    }

    private let type: Kind
    private let state: State
    private let action: () -> Void
    private let layout = LayoutTokens()

    public init(
        type: Kind = .audio,
        state: State = .default,
        action: @escaping () -> Void
    ) {
        self.type = type
        self.state = state
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            RecordButtonIcon(
                icon: type.icon,
                slotSize: layout.iconDefaultSize,
                artworkCanvasSize: type == .video ? layout.iconDefaultSize : 22
            )
        }
        .buttonStyle(
            RunIconButtonStyle(
                background: Color("Experiment/Fill/Secondary", bundle: .module),
                foreground: Color("Experiment/Label/Brand", bundle: .module),
                iconSize: layout.iconDefaultSize
            )
        )
        .disabled(state == .disabled)
        .accessibilityLabel(Text(type.accessibilityLabel))
        .accessibilityValue(Text(state.accessibilityValue))
    }
}

private struct RecordButtonIcon: View {
    private let icon: LabcordIcon
    private let artworkCanvasSize: CGFloat
    @ScaledMetric private var slotSize: CGFloat
    @ScaledMetric private var captureCanvasSize: CGFloat

    init(icon: LabcordIcon, slotSize: CGFloat, artworkCanvasSize: CGFloat) {
        self.icon = icon
        self.artworkCanvasSize = artworkCanvasSize
        _slotSize = ScaledMetric(wrappedValue: slotSize, relativeTo: .body)
        _captureCanvasSize = ScaledMetric(wrappedValue: artworkCanvasSize, relativeTo: .body)
    }

    var body: some View {
        artwork
            .frame(width: slotSize, height: slotSize)
    }

    @ViewBuilder
    private var artwork: some View {
        if icon == .capture {
            Image("labcord-record-capture", bundle: .module)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: captureCanvasSize, height: captureCanvasSize)
                .accessibilityHidden(true)
        } else {
            LabcordIconArtwork(icon: icon, size: artworkCanvasSize, relativeTo: .body)
        }
    }
}

private extension RecordButton.State {
    var accessibilityValue: String {
        switch self {
        case .default:
            "사용 가능"
        case .disabled:
            "사용할 수 없음"
        }
    }
}

#Preview("Record Button") {
    _ = FontRegistration.register()
    return HStack(spacing: 16) {
        RecordButton(type: .audio, action: noRecordAction)
        RecordButton(type: .capture, action: noRecordAction)
        RecordButton(type: .video, action: noRecordAction)
        RecordButton(type: .audio, state: .disabled, action: noRecordAction)
    }
    .padding()
    .background(Color("Experiment/Background/Primary", bundle: .module))
}

private func noRecordAction() { }
