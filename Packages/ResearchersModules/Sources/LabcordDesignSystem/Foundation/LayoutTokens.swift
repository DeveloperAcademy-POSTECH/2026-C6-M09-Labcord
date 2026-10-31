import CoreGraphics

public enum LayoutToken: String, CaseIterable, Sendable {
    case spacing2 = "spacing/2"
    case spacing4 = "spacing/4"
    case spacing8 = "spacing/8"
    case spacing12 = "spacing/12"
    case spacing16 = "spacing/16"
    case spacing24 = "spacing/24"
    case spacing32 = "spacing/32"
    case radiusSm = "radius/sm"
    case radiusMd = "radius/md"
    case radiusLg = "radius/lg"
    case radiusFull = "radius/full"
    case spacing20 = "spacing/20"
    case spacing10 = "spacing/10"
    case iconDefaultSize = "size/icon/default"
    case iconLargeSize = "size/icon/large"
    case controlDefaultSize = "size/control/default"
    case timerTabHeight = "size/timer-tab/height"
    case timerItemHeight = "size/timer-item/height"
}

public struct LayoutTokens: Sendable {
    public let spacing2: CGFloat
    public let spacing4: CGFloat
    public let spacing8: CGFloat
    public let spacing12: CGFloat
    public let spacing16: CGFloat
    public let spacing24: CGFloat
    public let spacing32: CGFloat
    public let radiusSm: CGFloat
    public let radiusMd: CGFloat
    public let radiusLg: CGFloat
    public let radiusFull: CGFloat
    public let spacing20: CGFloat
    public let spacing10: CGFloat
    public let iconDefaultSize: CGFloat
    public let iconLargeSize: CGFloat
    public let controlDefaultSize: CGFloat
    public let timerTabHeight: CGFloat
    public let timerItemHeight: CGFloat

    public init() {
        spacing2 = 2
        spacing4 = 4
        spacing8 = 8
        spacing12 = 12
        spacing16 = 16
        spacing24 = 24
        spacing32 = 32
        radiusSm = 8
        radiusMd = 12
        radiusLg = 16
        radiusFull = 999
        spacing20 = 20
        spacing10 = 10
        iconDefaultSize = 20
        iconLargeSize = 28
        controlDefaultSize = 50
        timerTabHeight = 54
        timerItemHeight = 60
    }

    public subscript(_ token: LayoutToken) -> CGFloat {
        switch token {
        case .spacing2:
            return spacing2
        case .spacing4:
            return spacing4
        case .spacing8:
            return spacing8
        case .spacing12:
            return spacing12
        case .spacing16:
            return spacing16
        case .spacing24:
            return spacing24
        case .spacing32:
            return spacing32
        case .radiusSm:
            return radiusSm
        case .radiusMd:
            return radiusMd
        case .radiusLg:
            return radiusLg
        case .radiusFull:
            return radiusFull
        case .spacing20:
            return spacing20
        case .spacing10:
            return spacing10
        case .iconDefaultSize:
            return iconDefaultSize
        case .iconLargeSize:
            return iconLargeSize
        case .controlDefaultSize:
            return controlDefaultSize
        case .timerTabHeight:
            return timerTabHeight
        case .timerItemHeight:
            return timerItemHeight
        }
    }
}
