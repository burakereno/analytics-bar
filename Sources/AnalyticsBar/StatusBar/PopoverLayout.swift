import CoreGraphics

enum PopoverLayout {
    static let width: CGFloat = 380
    static let initialHeight: CGFloat = 270
    static let preferredHeight: CGFloat = 680
    static let minimumHeight: CGFloat = 220
    static let screenMargin: CGFloat = 28

    static func clampedHeight(_ preferred: CGFloat, visibleScreenHeight: CGFloat) -> CGFloat {
        min(max(preferred, minimumHeight), max(minimumHeight, visibleScreenHeight - screenMargin))
    }
}
