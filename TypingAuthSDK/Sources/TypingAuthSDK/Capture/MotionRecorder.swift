import CoreMotion
import Foundation

public final class MotionRecorder {
    private let motionManager = CMMotionManager()
    private var snapshots: [MotionSnapshot] = []
    private var viewPresentedAt: TimeInterval = 0
    private let updateInterval: TimeInterval = 1.0 / 60.0 // 60Hz

    public init() {}

    public func start(viewPresentedAt: TimeInterval) {
        self.viewPresentedAt = viewPresentedAt
        snapshots.removeAll()

        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(to: .init()) { [weak self] motion, _ in
            guard let self, let motion else { return }

            let snapshot = MotionSnapshot(
                timestamp: motion.timestamp - self.viewPresentedAt,
                accelerometerX: motion.userAcceleration.x + motion.gravity.x,
                accelerometerY: motion.userAcceleration.y + motion.gravity.y,
                accelerometerZ: motion.userAcceleration.z + motion.gravity.z,
                gyroX: motion.rotationRate.x,
                gyroY: motion.rotationRate.y,
                gyroZ: motion.rotationRate.z,
                gravityX: motion.gravity.x,
                gravityY: motion.gravity.y,
                gravityZ: motion.gravity.z,
                userAccelX: motion.userAcceleration.x,
                userAccelY: motion.userAcceleration.y,
                userAccelZ: motion.userAcceleration.z,
                attitudePitch: motion.attitude.pitch,
                attitudeRoll: motion.attitude.roll,
                attitudeYaw: motion.attitude.yaw
            )

            DispatchQueue.main.async {
                self.snapshots.append(snapshot)
            }
        }
    }

    public func stop() {
        motionManager.stopDeviceMotionUpdates()
    }

    public func collectedSnapshots() -> [MotionSnapshot] {
        snapshots
    }

    public func reset() {
        snapshots.removeAll()
    }
}
