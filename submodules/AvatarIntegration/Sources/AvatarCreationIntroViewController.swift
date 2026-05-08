import SwiftUI
import UIKit

public final class AvatarCreationIntroViewController: UIHostingController<AvatarCreationIntroView> {
    private let onBack: (() -> Void)?

    public init(
        onBack: (() -> Void)? = nil,
        onCreateFromSelfie: (() -> Void)? = nil,
        onChooseAnimalAvatar: (() -> Void)? = nil,
        onCreateManually: (() -> Void)? = nil,
        onTermsOfService: (() -> Void)? = nil
    ) {
        self.onBack = onBack
        super.init(rootView: AvatarCreationIntroView(
            onBack: {},
            onCreateFromSelfie: onCreateFromSelfie,
            onChooseAnimalAvatar: onChooseAnimalAvatar,
            onCreateManually: onCreateManually,
            onTermsOfService: onTermsOfService
        ))
        self.rootView = AvatarCreationIntroView(
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
            onCreateFromSelfie: onCreateFromSelfie,
            onChooseAnimalAvatar: onChooseAnimalAvatar,
            onCreateManually: onCreateManually,
            onTermsOfService: onTermsOfService
        )
        self.modalPresentationStyle = .fullScreen
    }

    @MainActor public required dynamic init?(coder aDecoder: NSCoder) {
        self.onBack = nil
        super.init(coder: aDecoder, rootView: AvatarCreationIntroView())
    }
}
