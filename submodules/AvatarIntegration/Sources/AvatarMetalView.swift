#if canImport(UIKit)
import AvatarEngineBridge
import QuartzCore
import UIKit

public final class AvatarMetalView: UIView {
    public var maximumDrawableScale: CGFloat = .greatestFiniteMagnitude

    public override class var layerClass: AnyClass {
        AvatarEngineBridge.renderLayerClass()
    }

    public var renderLayer: CALayer {
        self.layer
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.configureLayer()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.configureLayer()
    }

    private func configureLayer() {
        self.isOpaque = true
        self.backgroundColor = .black
        AvatarEngineBridge.configureRenderLayer(self.layer, screenScale: UIScreen.main.scale)
    }

    public func updateDrawableSize() -> CGSize {
        let screenScale = self.window?.screen.scale ?? UIScreen.main.scale
        let scale = min(screenScale, max(1.0, self.maximumDrawableScale))
        let drawableSize = CGSize(
            width: max(1.0, self.bounds.width * scale),
            height: max(1.0, self.bounds.height * scale)
        )
        AvatarEngineBridge.updateRenderLayer(self.layer, screenScale: scale, drawableSize: drawableSize)
        return drawableSize
    }
}
#endif
