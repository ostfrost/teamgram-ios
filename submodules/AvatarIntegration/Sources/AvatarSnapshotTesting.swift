#if canImport(UIKit)
import Foundation
import UIKit

public struct AvatarSnapshotConfiguration: Equatable {
    public var size: CGSize
    public var scale: CGFloat
    public var paramsJSON: String
    public var framesToRender: Int

    public init(
        size: CGSize = CGSize(width: 512.0, height: 512.0),
        scale: CGFloat = 1.0,
        paramsJSON: String = AvatarSnapshotFixtures.baseAvatarParamsJSON,
        framesToRender: Int = 2
    ) {
        self.size = size
        self.scale = scale
        self.paramsJSON = paramsJSON
        self.framesToRender = framesToRender
    }
}

public struct AvatarSnapshotResult: Equatable {
    public var pngData: Data
    public var pixelSize: CGSize
    public var paramsJSON: String
}

public enum AvatarSnapshotError: Error, Equatable {
    case invalidSize
    case rendererFailed(String)
    case pngEncodingFailed
}

public enum AvatarSnapshotFixtures {
    public static var baseAvatarParamsJSON: String {
        guard let url = Bundle.module.url(
            forResource: "base-avatar-params",
            withExtension: "json"
        ), let data = try? Data(contentsOf: url), let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

@MainActor
public final class AvatarRendererSnapshotter {
    private weak var errorReporter: AvatarRendererErrorReporting?

    public init(errorReporter: AvatarRendererErrorReporting? = nil) {
        self.errorReporter = errorReporter
    }

    public func renderSnapshot(configuration: AvatarSnapshotConfiguration = AvatarSnapshotConfiguration()) throws -> AvatarSnapshotResult {
        guard configuration.size.width > 0.0, configuration.size.height > 0.0, configuration.scale > 0.0 else {
            throw AvatarSnapshotError.invalidSize
        }

        let view = AvatarMetalView(frame: CGRect(origin: .zero, size: configuration.size))
        _ = view.updateDrawableSize()

        let pixelSize = CGSize(
            width: configuration.size.width * configuration.scale,
            height: configuration.size.height * configuration.scale
        )

        do {
            let engine = try AvatarEngine(
                view: view,
                width: Int(pixelSize.width),
                height: Int(pixelSize.height)
            )
            try engine.setParamsJSON(configuration.paramsJSON)

            for _ in 0 ..< max(1, configuration.framesToRender) {
                try engine.render()
            }
        } catch {
            self.errorReporter?.recordAvatarRendererError(error, context: "renderSnapshot")
            throw AvatarSnapshotError.rendererFailed(String(describing: error))
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = configuration.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: configuration.size, format: format)
        let image = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: configuration.size))
            view.layer.render(in: context.cgContext)
        }

        guard let pngData = image.pngData() else {
            throw AvatarSnapshotError.pngEncodingFailed
        }

        return AvatarSnapshotResult(
            pngData: pngData,
            pixelSize: pixelSize,
            paramsJSON: configuration.paramsJSON
        )
    }
}
#endif
