import WatchKit

public enum WatchScreenMetrics {
    public static func scaledHeight(
        _ height: CGFloat,
        referenceHeight: CGFloat = 197
    ) -> CGFloat {
        WKInterfaceDevice.current().screenBounds.height * height / referenceHeight
    }
}
