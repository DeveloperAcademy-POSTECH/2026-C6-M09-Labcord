import CoreGraphics

public enum EffectToken: String, CaseIterable, Sendable {
    case blurSoftRadius = "Effect/Blur/Soft/Radius"
    case blurMediumRadius = "Effect/Blur/Medium/Radius"
    case blurStrongRadius = "Effect/Blur/Strong/Radius"
    case shadowSoftRadius = "Effect/Shadow/Soft/Radius"
    case shadowSoftOffsetY = "Effect/Shadow/Soft/OffsetY"
    case shadowSoftSpread = "Effect/Shadow/Soft/Spread"
    case shadowMediumRadius = "Effect/Shadow/Medium/Radius"
    case shadowMediumOffsetY = "Effect/Shadow/Medium/OffsetY"
    case shadowMediumSpread = "Effect/Shadow/Medium/Spread"
    case shadowStrongRadius = "Effect/Shadow/Strong/Radius"
    case shadowStrongOffsetY = "Effect/Shadow/Strong/OffsetY"
    case shadowStrongSpread = "Effect/Shadow/Strong/Spread"
}

public struct EffectTokens: Sendable {
    public let blurSoftRadius: CGFloat
    public let blurMediumRadius: CGFloat
    public let blurStrongRadius: CGFloat
    public let shadowSoftRadius: CGFloat = 8
    public let shadowSoftOffsetY: CGFloat = 2
    public let shadowSoftSpread: CGFloat = 0
    public let shadowMediumRadius: CGFloat = 20
    public let shadowMediumOffsetY: CGFloat = 6
    public let shadowMediumSpread: CGFloat = 0
    public let shadowStrongRadius: CGFloat = 36
    public let shadowStrongOffsetY: CGFloat = 12
    public let shadowStrongSpread: CGFloat = 0

    public init(context: ThemeContext = .general) {
        if context == .experiment {
            blurSoftRadius = 12
            blurMediumRadius = 24
            blurStrongRadius = 40
        } else {
            blurSoftRadius = 8
            blurMediumRadius = 16
            blurStrongRadius = 24
        }
    }

    public subscript(_ token: EffectToken) -> CGFloat {
        switch token {
        case .blurSoftRadius:
            return blurSoftRadius
        case .blurMediumRadius:
            return blurMediumRadius
        case .blurStrongRadius:
            return blurStrongRadius
        case .shadowSoftRadius:
            return shadowSoftRadius
        case .shadowSoftOffsetY:
            return shadowSoftOffsetY
        case .shadowSoftSpread:
            return shadowSoftSpread
        case .shadowMediumRadius:
            return shadowMediumRadius
        case .shadowMediumOffsetY:
            return shadowMediumOffsetY
        case .shadowMediumSpread:
            return shadowMediumSpread
        case .shadowStrongRadius:
            return shadowStrongRadius
        case .shadowStrongOffsetY:
            return shadowStrongOffsetY
        case .shadowStrongSpread:
            return shadowStrongSpread
        }
    }
}
