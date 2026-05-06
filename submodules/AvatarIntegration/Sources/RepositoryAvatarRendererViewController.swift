#if canImport(UIKit)
import UIKit

public final class RepositoryAvatarRendererViewController: UIViewController, UIGestureRecognizerDelegate {
    private final class DisplayLinkTarget: NSObject {
        weak var owner: RepositoryAvatarRendererViewController?

        init(owner: RepositoryAvatarRendererViewController) {
            self.owner = owner
        }

        @objc func renderFrame(_ displayLink: CADisplayLink) {
            self.owner?.renderFrame(displayLink: displayLink)
        }
    }

    public let avatarView = AvatarRepositoryMetalView(frame: .zero)

    private let configuration: AvatarRendererConfiguration
    private let onError: ((Error) -> Void)?
    private weak var errorReporter: AvatarRendererErrorReporting?
    private var engine: RepositoryAvatarEngine?
    private var displayLink: CADisplayLink?
    private var displayLinkTarget: DisplayLinkTarget?
    private var lastDrawableSize: CGSize = .zero
    private var rotationYaw: Float = 0.0
    private var rotationPitch: Float = 0.0
    private var panGestureRecognizer: UIPanGestureRecognizer?
    private var isRendererVisible = false
    private var pendingFrameCount = 0

    public init(
        configuration: AvatarRendererConfiguration = AvatarRendererConfiguration(),
        errorReporter: AvatarRendererErrorReporting? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.errorReporter = errorReporter
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        self.configuration = AvatarRendererConfiguration()
        self.errorReporter = nil
        self.onError = nil
        super.init(coder: coder)
    }

    deinit {
        self.releaseEngine()
    }

    public override func loadView() {
        self.avatarView.maximumDrawableScale = self.configuration.maximumDrawableScale
        self.view = self.avatarView
        self.view.isUserInteractionEnabled = true
        self.view.backgroundColor = .black

        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(self.handlePan(_:)))
        panGestureRecognizer.delegate = self
        panGestureRecognizer.cancelsTouchesInView = false
        panGestureRecognizer.delaysTouchesBegan = false
        panGestureRecognizer.delaysTouchesEnded = false
        self.view.addGestureRecognizer(panGestureRecognizer)
        self.panGestureRecognizer = panGestureRecognizer
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if self.avatarView !== self.view {
            self.avatarView.frame = self.view.bounds
        }

        let drawableSize = self.avatarView.updateDrawableSize()
        guard drawableSize != self.lastDrawableSize else {
            self.requestRender(frames: 1)
            return
        }
        self.lastDrawableSize = drawableSize

        if let engine = self.engine {
            do {
                try engine.resize(width: Int(drawableSize.width), height: Int(drawableSize.height))
            } catch {
                NSLog("AvatarIntegration: repository resize failed: \(error)")
                self.report(error, context: "repository.resize")
            }
        } else if self.isRendererVisible && drawableSize.width > 16.0 && drawableSize.height > 16.0 {
            self.createEngine(drawableSize: drawableSize)
        }
        self.requestRender(frames: 2)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.isRendererVisible = true
        self.requestRender(frames: 3)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.isRendererVisible = true
        self.requestRender(frames: 2)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.isRendererVisible = false
        self.stopRenderLoop()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.releaseEngine()
    }

    private func createEngine(drawableSize: CGSize) {
        do {
            let engine = try RepositoryAvatarEngine(
                view: self.avatarView,
                width: Int(drawableSize.width),
                height: Int(drawableSize.height),
                modelData: self.configuration.modelData ?? AvatarModelResource.defaultModelData()
            )
            try engine.setParamsJSON(self.configuration.initialParamsJSON)
            try engine.setRotation(yaw: self.rotationYaw, pitch: self.rotationPitch)
            try engine.setAutomaticRotation(
                enabled: self.shouldAdvanceAutomaticRotation,
                speed: self.configuration.automaticRotationSpeedRadiansPerSecond
            )
            self.engine = engine
            NSLog("AvatarIntegration: created repository avatar-engine for drawable %.0fx%.0f", drawableSize.width, drawableSize.height)
            self.requestRender(frames: 3)
        } catch {
            NSLog("AvatarIntegration: repository createEngine failed: \(error)")
            self.report(error, context: "repository.createEngine")
        }
    }

    private func releaseEngine() {
        self.stopRenderLoop()
        self.engine = nil
        self.lastDrawableSize = .zero
        self.pendingFrameCount = 0
    }

    private var shouldAdvanceAutomaticRotation: Bool {
        return self.configuration.automaticallyRotates
            && self.configuration.automaticRotationSpeedRadiansPerSecond.isFinite
            && self.configuration.automaticRotationSpeedRadiansPerSecond != 0.0
    }

    private var keepsRenderLoopActive: Bool {
        return self.configuration.rendersContinuously || self.shouldAdvanceAutomaticRotation
    }

    private func requestRender(frames: Int) {
        guard self.isRendererVisible else {
            return
        }
        self.pendingFrameCount = max(self.pendingFrameCount, frames)
        self.startRenderLoop()
    }

    private func startRenderLoop() {
        guard self.displayLink == nil else {
            return
        }
        guard self.isRendererVisible else {
            return
        }
        guard self.keepsRenderLoopActive || self.pendingFrameCount > 0 else {
            return
        }

        let target = DisplayLinkTarget(owner: self)
        let displayLink = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.renderFrame(_:)))
        displayLink.preferredFramesPerSecond = self.configuration.preferredFramesPerSecond
        displayLink.add(to: .main, forMode: .common)
        self.displayLinkTarget = target
        self.displayLink = displayLink
    }

    private func stopRenderLoop() {
        self.displayLink?.invalidate()
        self.displayLink = nil
        self.displayLinkTarget = nil
    }

    private func renderFrame(displayLink: CADisplayLink) {
        guard self.isRendererVisible else {
            self.stopRenderLoop()
            return
        }

        let keepsRenderLoopActive = self.keepsRenderLoopActive
        if !keepsRenderLoopActive && self.pendingFrameCount == 0 {
            self.stopRenderLoop()
            return
        }
        if self.pendingFrameCount > 0 {
            self.pendingFrameCount -= 1
        }

        if self.engine == nil {
            let drawableSize = self.avatarView.updateDrawableSize()
            self.lastDrawableSize = drawableSize
            if drawableSize.width > 16.0 && drawableSize.height > 16.0 {
                self.createEngine(drawableSize: drawableSize)
            } else {
                self.stopRenderLoop()
            }
            return
        }

        guard let engine = self.engine else {
            return
        }

        do {
            try engine.render(at: displayLink.timestamp)
        } catch {
            NSLog("AvatarIntegration: repository renderFrame failed: \(error)")
            self.stopRenderLoop()
            self.report(error, context: "repository.renderFrame")
        }

        if !keepsRenderLoopActive && self.pendingFrameCount == 0 {
            self.stopRenderLoop()
        }
    }

    @objc private func handlePan(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard gestureRecognizer.state == .began || gestureRecognizer.state == .changed else {
            return
        }

        let translation = gestureRecognizer.translation(in: self.view)
        gestureRecognizer.setTranslation(.zero, in: self.view)

        guard translation != .zero else {
            return
        }

        do {
            try self.engine?.addRotation(
                yawDelta: Float(translation.x) * 0.01,
                pitchDelta: Float(translation.y) * 0.01
            )
            self.requestRender(frames: 2)
        } catch {
            self.report(error, context: "repository.addRotation")
        }
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return gestureRecognizer === self.panGestureRecognizer
    }

    private func report(_ error: Error, context: String) {
        self.errorReporter?.recordAvatarRendererError(error, context: context)
        self.onError?(error)
    }
}
#endif
