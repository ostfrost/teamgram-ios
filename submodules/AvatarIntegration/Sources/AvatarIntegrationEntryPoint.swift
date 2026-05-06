#if canImport(UIKit)
import UIKit

public enum AvatarIntegrationEntryPoint {
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
