#if canImport(UIKit)
import Foundation

public enum AvatarModelResource {
    public static func defaultModelData() -> Data? {
        return self.modelData(named: "avatar-model", extension: "glb")
    }

    private static func modelData(named name: String, extension ext: String) -> Data? {
        for bundle in AvatarResourceBundle.candidateBundles() {
            for subdirectory in ["Models", "Sources/Resources/Models", nil] as [String?] {
                if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory),
                   let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
                    return data
                }
            }
        }
        return nil
    }
}
#endif
