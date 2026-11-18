import WatchKit

public enum WatchScreenMetrics {
    public static func scaledWidth(
        _ width: CGFloat,
        referenceWidth: CGFloat = 162
    ) -> CGFloat {
        WKInterfaceDevice.current().screenBounds.width * width / referenceWidth
    }

    public static func scaledHeight(
        _ height: CGFloat,
        referenceHeight: CGFloat = 197
    ) -> CGFloat {
        WKInterfaceDevice.current().screenBounds.height * height / referenceHeight
    }
}
