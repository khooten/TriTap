import UIKit

public final class PasscodeDotsView: UIView {
    private let dotCount: Int
    private var filledCount = 0
    private var dotLayers: [CAShapeLayer] = []

    private let dotSize: CGFloat = 14
    private let dotSpacing: CGFloat = 20

    public init(count: Int = 6) {
        self.dotCount = count
        super.init(frame: .zero)
        setupDots()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setupDots() {
        for _ in 0..<dotCount {
            let layer = CAShapeLayer()
            layer.strokeColor = UIColor.label.cgColor
            layer.lineWidth = 1.5
            layer.fillColor = UIColor.clear.cgColor
            self.layer.addSublayer(layer)
            dotLayers.append(layer)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let totalWidth = CGFloat(dotCount) * dotSize + CGFloat(dotCount - 1) * dotSpacing
        var x = (bounds.width - totalWidth) / 2

        for layer in dotLayers {
            layer.path = UIBezierPath(ovalIn: CGRect(x: x, y: (bounds.height - dotSize) / 2, width: dotSize, height: dotSize)).cgPath
            x += dotSize + dotSpacing
        }
        updateFill()
    }

    public func setFilledCount(_ count: Int) {
        filledCount = count
        updateFill()
    }

    private func updateFill() {
        for (i, layer) in dotLayers.enumerated() {
            layer.fillColor = i < filledCount ? UIColor.label.cgColor : UIColor.clear.cgColor
        }
    }

    public override var intrinsicContentSize: CGSize {
        let totalWidth = CGFloat(dotCount) * dotSize + CGFloat(dotCount - 1) * dotSpacing
        return CGSize(width: totalWidth, height: dotSize + 8)
    }

    public func shake() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.4
        animation.values = [-10, 10, -8, 8, -5, 5, 0]
        layer.add(animation, forKey: "shake")
    }
}
