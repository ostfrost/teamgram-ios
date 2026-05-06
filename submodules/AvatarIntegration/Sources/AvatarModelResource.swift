#if canImport(UIKit)
import Foundation

private final class AvatarModelBundleToken {
}

public enum AvatarModelResource {
    public static func defaultModelData() -> Data? {
        return self.modelData(named: "avatar-model", extension: "glb")
    }

    private static func modelData(named name: String, extension ext: String) -> Data? {
        for bundle in self.candidateBundles() {
            for subdirectory in ["Models", "Sources/Resources/Models", nil] as [String?] {
                if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory),
                   let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
                    return data
                }
            }
        }
        return nil
    }

    private static func candidateBundles() -> [Bundle] {
        var bundles: [Bundle] = []

#if SWIFT_PACKAGE
        bundles.append(Bundle.module)
#endif

        let classBundle = Bundle(for: AvatarModelBundleToken.self)
        bundles.append(classBundle)
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
        bundles.append(Bundle.main)

        return bundles
    }
}
#endif
