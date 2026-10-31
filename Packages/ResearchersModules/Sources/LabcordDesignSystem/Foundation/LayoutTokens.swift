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
    public init() {}

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
