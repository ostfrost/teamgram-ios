#if canImport(UIKit)
import UIKit

public final class AvatarFlowViewController: UIViewController {
    private let onClose: (() -> Void)?
    private let navigation: AvatarFlowNavigationController

    public init(
        onClose: (() -> Void)? = nil,
        onCreateFromSelfie: (() -> Void)? = nil,
        onChooseAnimalAvatar: (() -> Void)? = nil,
        onCreateManually: (() -> Void)? = nil,
        onTermsOfService: (() -> Void)? = nil
    ) {
        self.onClose = onClose
        self.navigation = AvatarFlowNavigationController()
        super.init(nibName: nil, bundle: nil)

        self.navigation.setNavigationBarHidden(true, animated: false)

        let rootController = AvatarSelfieIntroViewController(
            onBack: { [weak self] in
                self?.onClose?()
            },
            onCreateAvatar: { [weak self] in
                self?.openCreationIntro(
                    onCreateFromSelfie: onCreateFromSelfie,
                    onChooseAnimalAvatar: onChooseAnimalAvatar,
                    onCreateManually: onCreateManually,
                    onTermsOfService: onTermsOfService
                )
            }
        )
        self.navigation.setViewControllers([rootController], animated: false)
        self.modalPresentationStyle = .fullScreen
    }

    @MainActor public required dynamic init?(coder aDecoder: NSCoder) {
        self.onClose = nil
        self.navigation = AvatarFlowNavigationController()
        super.init(coder: aDecoder)
        self.navigation.setNavigationBarHidden(true, animated: false)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        self.addChild(self.navigation)
        self.navigation.view.frame = self.view.bounds
        self.navigation.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(self.navigation.view)
        self.navigation.didMove(toParent: self)
    }

    private func openCreationIntro(
        onCreateFromSelfie: (() -> Void)?,
        onChooseAnimalAvatar: (() -> Void)?,
        onCreateManually: (() -> Void)?,
        onTermsOfService: (() -> Void)?
    ) {
        let controller = AvatarCreationIntroViewController(
            onBack: { [weak self] in
                self?.navigation.popViewController(animated: true)
            },
            onCreateFromSelfie: onCreateFromSelfie,
            onChooseAnimalAvatar: onChooseAnimalAvatar,
            onCreateManually: { [weak self] in
                if let onCreateManually = onCreateManually {
                    onCreateManually()
                } else {
                    self?.openManualRenderer()
                }
            },
            onTermsOfService: onTermsOfService
        )
        self.navigation.pushViewController(controller, animated: true)
    }

    private func openManualRenderer() {
        let controller = AvatarRendererViewController(
            configuration: AvatarRendererConfiguration(
                backend: .current,
                rendersContinuously: false,
                automaticallyRotates: true
            )
        )
        self.navigation.pushViewController(controller, animated: true)
    }
}

private final class AvatarFlowNavigationController: UINavigationController, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()

        self.delegate = self
        self.setNavigationBarHidden(true, animated: false)
        self.view.backgroundColor = .black
        self.interactivePopGestureRecognizer?.delegate = self
        self.interactivePopGestureRecognizer?.isEnabled = true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === self.interactivePopGestureRecognizer {
            return self.viewControllers.count > 1
        }
        return true
    }

    func navigationController(
        _ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from fromVC: UIViewController,
        to toVC: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        switch operation {
        case .push, .pop:
            return AvatarFlowSlideAnimator(operation: operation)
        default:
            return nil
        }
    }
}

private final class AvatarFlowSlideAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let operation: UINavigationController.Operation

    init(operation: UINavigationController.Operation) {
        self.operation = operation
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.32
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to),
              let toViewController = transitionContext.viewController(forKey: .to) else {
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }

        let containerView = transitionContext.containerView
        let width = containerView.bounds.width
        let isPush = self.operation == .push
        let finalToFrame = transitionContext.finalFrame(for: toViewController)
        let initialFromFrame = fromView.frame
        let initialToFrame = finalToFrame.offsetBy(dx: isPush ? width : -width * 0.28, dy: 0.0)

        toView.frame = initialToFrame
        if isPush {
            containerView.addSubview(toView)
        } else {
            containerView.insertSubview(toView, belowSubview: fromView)
        }

        let animations = {
            if isPush {
                fromView.frame = initialFromFrame.offsetBy(dx: -width * 0.28, dy: 0.0)
                toView.frame = finalToFrame
            } else {
                fromView.frame = initialFromFrame.offsetBy(dx: width, dy: 0.0)
                toView.frame = finalToFrame
            }
        }

        UIView.animate(
            withDuration: self.transitionDuration(using: transitionContext),
            delay: 0.0,
            options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState],
            animations: animations,
            completion: { _ in
                let cancelled = transitionContext.transitionWasCancelled
                fromView.frame = cancelled ? initialFromFrame : fromView.frame
                toView.frame = cancelled ? initialToFrame : finalToFrame
                transitionContext.completeTransition(!cancelled)
            }
        )
    }
}
#endif
