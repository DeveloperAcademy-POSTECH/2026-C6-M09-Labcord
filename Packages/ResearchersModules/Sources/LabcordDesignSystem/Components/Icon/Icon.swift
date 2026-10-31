import SwiftUI

public enum Icon: String, CaseIterable, Identifiable, Sendable {
    case arrowCounterClockwiseBold = "arrow-counter-clockwise-bold"
    case arrowCounterClockwise = "arrow-counter-clockwise"
    case arrowIn = "arrow-in"
    case arrowOut = "arrow-out"
    case arrowsCounterClockwise = "arrows-counter-clockwise"
    case cameraFill = "camera-fill"
    case capture = "capture"
    case caretDown = "caret-down"
    case caretLeft = "caret-left"
    case caretRight = "caret-right"
    case caretUp = "caret-up"
    case checkBold = "check-bold"
    case checkCircleFill = "check-circle-fill"
    case check = "check"
    case dot = "dot"
    case dotsThreeOutline = "dots-three-outline"
    case dotsThreeVertical = "dots-three-vertical"
    case dotsThree = "dots-three"
    case fileText = "file-text"
    case flask = "flask"
    case folderOpen = "folder-open"
    case gear = "gear"
    case houseFill = "house-fill"
    case image = "image"
    case linkBreak = "link-break"
    case microphoneFill = "microphone-fill"
    case mute = "mute"
    case pause = "pause"
    case pencilSimple = "pencil-simple"
    case play = "play"
    case plus = "plus"
    case prohibitInsert = "prohibit-insert"
    case questionmark = "questionmark"
    case record = "record"
    case rectangleLandscapeRotate = "rectangle-landscape-rotate"
    case rectanglePortraitRotate = "rectangle-portrait-rotate"
    case replay = "replay"
    case slidersHorizontal = "sliders-horizontal"
    case stop = "stop"
    case timerFill = "timer-fill"
    case timer = "timer"
    case trash = "trash"
    case uploadSimple = "upload-simple"
    case videocameraFill = "videocamera-fill"
    case warningCircle = "warning-circle"
    case warning = "warning"
    case watchCheck = "watch-check"
    case watch = "watch"
    case waveform = "waveform"
    case xBold = "x-bold"
    case xCircle = "x-circle"
    // swiftlint:disable:next identifier_name
    case x = "x"

    public var id: String {
        rawValue
    }

    fileprivate var symbolAssetName: String {
        "labcord-symbol-\(rawValue)"
    }

}

public extension Image {
    init(labcordIcon icon: Icon) {
        self.init(icon.symbolAssetName, bundle: .module)
    }
}

struct LabcordIconArtwork: View {
    private let icon: Icon
    @ScaledMetric private var scaledSize: CGFloat

    init(
        icon: Icon,
        size: CGFloat,
        relativeTo: Font.TextStyle = .body
    ) {
        self.icon = icon
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
    }

    var body: some View {
        Image(labcordIcon: icon)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: scaledSize, height: scaledSize)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            .accessibilityHidden(true)
    }
}

#Preview("아이콘") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 16) {
            ForEach(Icon.allCases) { icon in
                VStack(spacing: 4) {
                    LabcordIconArtwork(icon: icon, size: 24)
                    Text(icon.rawValue)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding()
    }
}

public typealias LabcordIcon = Icon
