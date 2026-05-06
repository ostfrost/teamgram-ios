#if canImport(UIKit)
import AvatarEngineBridge
import Foundation

public enum AvatarEngineError: Error, Equatable {
    case bridgeUnavailable
    case invalidNativeHandle
    case nativeCallFailed(String)
}

public struct MorphTarget: Hashable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public final class AvatarEngine {
    private let handle: UnsafeMutableRawPointer

    public init(view: AvatarMetalView, width: Int, height: Int, modelData: Data? = nil) throws {
        guard let handle = AvatarEngineBridge.create(
            with: view.renderLayer,
            width: width,
            height: height,
            modelData: modelData
        ) else {
            throw AvatarEngineError.bridgeUnavailable
        }
        self.handle = handle
    }

    deinit {
        AvatarEngineBridge.destroy(handle)
    }

    public func resize(width: Int, height: Int) throws {
        guard AvatarEngineBridge.resize(withHandle: handle, width: width, height: height) else {
            throw AvatarEngineError.nativeCallFailed("resize")
        }
    }

    public func setParamsJSON(_ json: String) throws {
        guard AvatarEngineBridge.setParamsJSON(json, handle: handle) else {
            throw AvatarEngineError.nativeCallFailed("setParamsJSON")
        }
    }

    public func equipItem(_ itemID: String) throws {
        guard AvatarEngineBridge.equipItem(itemID, handle: handle) else {
            throw AvatarEngineError.nativeCallFailed("equipItem")
        }
    }

    public func setMorph(_ target: MorphTarget, _ value: Float) throws {
        guard AvatarEngineBridge.setMorph(target.rawValue, value: value, handle: handle) else {
            throw AvatarEngineError.nativeCallFailed("setMorph")
        }
    }

    public func playEmotion(_ id: String) throws {
        guard AvatarEngineBridge.playEmotion(id, handle: handle) else {
            throw AvatarEngineError.nativeCallFailed("playEmotion")
        }
    }

    public func setRotation(yaw: Float, pitch: Float) throws {
        guard AvatarEngineBridge.setRotationYaw(yaw, pitch: pitch, handle: handle) else {
            throw AvatarEngineError.nativeCallFailed("setRotation")
        }
    }

    public func addRotation(yawDelta: Float, pitchDelta: Float) throws {
        guard AvatarEngineBridge.addRotationYaw(yawDelta, pitch: pitchDelta, handle: handle) else {
            throw AvatarEngineError.nativeCallFailed("addRotation")
        }
    }

    public func setAutomaticRotation(enabled: Bool, speed: Float) throws {
        guard AvatarEngineBridge.setAutomaticRotationEnabled(enabled, speed: speed, handle: handle) else {
            throw AvatarEngineError.nativeCallFailed("setAutomaticRotation")
        }
    }

    public func render() throws {
        guard AvatarEngineBridge.renderFrame(withHandle: handle) else {
            throw AvatarEngineError.nativeCallFailed("renderFrame")
        }
    }

    public func render(at timestamp: CFTimeInterval) throws {
        guard AvatarEngineBridge.renderFrame(withHandle: handle, timestamp: timestamp) else {
            throw AvatarEngineError.nativeCallFailed("renderFrame")
        }
    }
}
#endif
