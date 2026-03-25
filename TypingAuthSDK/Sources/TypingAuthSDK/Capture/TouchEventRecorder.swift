import UIKit

public final class TouchEventRecorder {
    private var events: [TouchEvent] = []
    private let viewPresentedAt: TimeInterval
    private var currentSequencePosition = 0

    // Intermediate samples accumulated during a key press
    private var intermediateRadii: [CGFloat] = []

    public init(viewPresentedAt: TimeInterval) {
        self.viewPresentedAt = viewPresentedAt
    }

    public func recordTouchBegan(_ touch: UITouch, in view: UIView, keyBounds: CGRect) {
        let location = touch.location(in: view)
        let normalizedX = (location.x - keyBounds.minX) / keyBounds.width
        let normalizedY = (location.y - keyBounds.minY) / keyBounds.height

        // Start collecting radius samples
        intermediateRadii = [touch.majorRadius]

        let event = TouchEvent(
            sequencePosition: currentSequencePosition,
            touchBegan: touch.timestamp - viewPresentedAt,
            touchEnded: 0,
            locationX: location.x,
            locationY: location.y,
            normalizedKeyX: min(max(normalizedX, 0), 1),
            normalizedKeyY: min(max(normalizedY, 0), 1),
            majorRadius: touch.majorRadius,
            majorRadiusTolerance: touch.majorRadiusTolerance
        )
        events.append(event)
    }

    /// Record intermediate touch data during the press (touchesMoved)
    public func recordTouchMoved(_ touch: UITouch) {
        guard !events.isEmpty else { return }
        intermediateRadii.append(touch.majorRadius)
    }

    /// Record touch end with the same coordinate space as begin
    public func recordTouchEnded(_ touch: UITouch, in view: UIView, keyBounds: CGRect) {
        guard !events.isEmpty else { return }
        intermediateRadii.append(touch.majorRadius)

        let index = events.count - 1
        let existing = events[index]
        let endTimestamp = touch.timestamp - viewPresentedAt

        // Compute end position in the SAME coordinate space as begin
        let endLocation = touch.location(in: view)
        let endNormX = (endLocation.x - keyBounds.minX) / keyBounds.width
        let endNormY = (endLocation.y - keyBounds.minY) / keyBounds.height

        // Radius profile from all intermediate samples
        let radMin = intermediateRadii.min() ?? existing.majorRadius
        let radMax = intermediateRadii.max() ?? existing.majorRadius
        let radMean = intermediateRadii.isEmpty
            ? existing.majorRadius
            : intermediateRadii.reduce(0, +) / CGFloat(intermediateRadii.count)

        events[index] = TouchEvent(
            sequencePosition: existing.sequencePosition,
            touchBegan: existing.touchBegan,
            touchEnded: endTimestamp,
            locationX: existing.locationX,
            locationY: existing.locationY,
            normalizedKeyX: existing.normalizedKeyX,
            normalizedKeyY: existing.normalizedKeyY,
            majorRadius: existing.majorRadius,
            majorRadiusTolerance: existing.majorRadiusTolerance,
            endLocationX: endLocation.x,
            endLocationY: endLocation.y,
            endNormalizedKeyX: min(max(endNormX, 0), 1),
            endNormalizedKeyY: min(max(endNormY, 0), 1),
            radiusMin: radMin,
            radiusMax: radMax,
            radiusMean: radMean,
            radiusSampleCount: intermediateRadii.count
        )
        currentSequencePosition += 1
        intermediateRadii = []
    }

    /// Fallback: record touch end without position data
    public func recordTouchEnded(_ touch: UITouch) {
        guard !events.isEmpty else { return }
        intermediateRadii.append(touch.majorRadius)
        finalizeWithoutPosition(endTimestamp: touch.timestamp - viewPresentedAt)
    }

    public func recordTouchEndedNow() {
        guard !events.isEmpty else { return }
        finalizeWithoutPosition(endTimestamp: ProcessInfo.processInfo.systemUptime - viewPresentedAt)
    }

    private func finalizeWithoutPosition(endTimestamp: TimeInterval) {
        let index = events.count - 1
        let existing = events[index]

        let radMin = intermediateRadii.min() ?? existing.majorRadius
        let radMax = intermediateRadii.max() ?? existing.majorRadius
        let radMean = intermediateRadii.isEmpty
            ? existing.majorRadius
            : intermediateRadii.reduce(0, +) / CGFloat(intermediateRadii.count)

        events[index] = TouchEvent(
            sequencePosition: existing.sequencePosition,
            touchBegan: existing.touchBegan,
            touchEnded: endTimestamp,
            locationX: existing.locationX,
            locationY: existing.locationY,
            normalizedKeyX: existing.normalizedKeyX,
            normalizedKeyY: existing.normalizedKeyY,
            majorRadius: existing.majorRadius,
            majorRadiusTolerance: existing.majorRadiusTolerance,
            endLocationX: existing.locationX,   // Same as begin (no end position data)
            endLocationY: existing.locationY,
            endNormalizedKeyX: existing.normalizedKeyX,
            endNormalizedKeyY: existing.normalizedKeyY,
            radiusMin: radMin,
            radiusMax: radMax,
            radiusMean: radMean,
            radiusSampleCount: intermediateRadii.count
        )
        currentSequencePosition += 1
        intermediateRadii = []
    }

    public func collectedEvents() -> [TouchEvent] {
        events
    }

    public func reset() {
        events.removeAll()
        currentSequencePosition = 0
        intermediateRadii = []
    }
}
