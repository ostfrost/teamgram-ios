import AvatarPeerInfoIntegration
import UIKit

@objc(Application) class Application: UIApplication {
    override init() {
        super.init()
        AvatarPeerInfoIntegration.install()
    }

    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)
    }
}
