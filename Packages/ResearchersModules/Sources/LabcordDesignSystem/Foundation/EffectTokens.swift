import CoreGraphics

public enum EffectContext: Sendable {
    case general
    case experiment
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

    public init(context: EffectContext = .general) {
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
}
