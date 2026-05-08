import Foundation

final class AvatarResourceBundleToken {
}

enum AvatarResourceBundle {
    static var bundle: Bundle? {
        return self.candidateBundles().first
    }

    static func candidateBundles() -> [Bundle] {
        var bundles: [Bundle] = []

#if SWIFT_PACKAGE
        bundles.append(Bundle.module)
#endif

        let classBundle = Bundle(for: AvatarResourceBundleToken.self)
        for bundleName in ["AvatarIntegration_AvatarIntegration", "AvatarIntegrationBundle"] {
            if let path = classBundle.path(forResource: bundleName, ofType: "bundle"),
               let bundle = Bundle(path: path) {
                bundles.append(bundle)
            }
            if let path = Bundle.main.path(forResource: bundleName, ofType: "bundle"),
               let bundle = Bundle(path: path) {
                bundles.append(bundle)
            }
        }
        bundles.append(classBundle)
        bundles.append(Bundle.main)

        return bundles
    }
}
