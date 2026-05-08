import SwiftUI
import UIKit

public final class AvatarSelfieIntroViewController: UIHostingController<AvatarSelfieIntroView> {
    private let onBack: (() -> Void)?
    private let onCreateAvatar: (() -> Void)?

    public init(
        onBack: (() -> Void)? = nil,
        onCreateAvatar: (() -> Void)? = nil,
        onLearnMore: (() -> Void)? = nil
    ) {
        self.onBack = onBack
        self.onCreateAvatar = onCreateAvatar
        super.init(rootView: AvatarSelfieIntroView(
            onBack: {},
            onCreateAvatar: nil,
            onLearnMore: onLearnMore
        ))
        self.rootView = AvatarSelfieIntroView(
            onBack: { [weak self] in
                guard let self else {
                    return
                }
                if let onBack = self.onBack {
                    onBack()
                } else if let navigationController = self.navigationController {
                    navigationController.popViewController(animated: true)
                } else {
                    self.dismiss(animated: true)
                }
            },
            onCreateAvatar: { [weak self] in
                guard let self else {
                    return
                }
                self.onCreateAvatar?()
            },
            onLearnMore: onLearnMore
        )
        self.modalPresentationStyle = .fullScreen
    }

    @MainActor public required dynamic init?(coder aDecoder: NSCoder) {
        self.onBack = nil
        self.onCreateAvatar = nil
        super.init(coder: aDecoder, rootView: AvatarSelfieIntroView())
    }
}
