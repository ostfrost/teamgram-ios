#if canImport(UIKit)
import UIKit

public enum AvatarIntegrationEntryPoint {
    public static func makeAvatarFlowViewController(
        onClose: (() -> Void)? = nil,
        onCreateFromSelfie: (() -> Void)? = nil,
        onChooseAnimalAvatar: (() -> Void)? = nil,
        onCreateManually: (() -> Void)? = nil,
        onTermsOfService: (() -> Void)? = nil
    ) -> UIViewController {
        AvatarFlowViewController(
            onClose: onClose,
            onCreateFromSelfie: onCreateFromSelfie,
            onChooseAnimalAvatar: onChooseAnimalAvatar,
            onCreateManually: onCreateManually,
            onTermsOfService: onTermsOfService
        )
    }

    public static func makeSelfieIntroViewController(
        onBack: (() -> Void)? = nil,
        onCreateAvatar: (() -> Void)? = nil,
        onLearnMore: (() -> Void)? = nil
    ) -> UIViewController {
        AvatarSelfieIntroViewController(
            onBack: onBack,
            onCreateAvatar: onCreateAvatar,
            onLearnMore: onLearnMore
        )
    }

    public static func makeAvatarCreationIntroViewController(
        onBack: (() -> Void)? = nil,
        onCreateFromSelfie: (() -> Void)? = nil,
        onChooseAnimalAvatar: (() -> Void)? = nil,
        onCreateManually: (() -> Void)? = nil,
        onTermsOfService: (() -> Void)? = nil
    ) -> UIViewController {
        AvatarCreationIntroViewController(
            onBack: onBack,
            onCreateFromSelfie: onCreateFromSelfie,
            onChooseAnimalAvatar: onChooseAnimalAvatar,
            onCreateManually: onCreateManually,
            onTermsOfService: onTermsOfService
        )
    }

    public static func makeDebugRendererViewController(
        configuration: AvatarRendererConfiguration = AvatarRendererConfiguration(),
        errorReporter: AvatarRendererErrorReporting? = nil,
        onError: ((Error) -> Void)? = nil
    ) -> UIViewController {
        switch configuration.backend {
        case .current, .repository:
            return AvatarRendererViewController(
                configuration: configuration,
                errorReporter: errorReporter,
                onError: onError
            )
        }
    }
}
#endif
