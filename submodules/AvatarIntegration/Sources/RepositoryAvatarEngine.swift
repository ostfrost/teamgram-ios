#if canImport(UIKit)
import AvatarEngineBridge
import Foundation

public final class RepositoryAvatarEngine {
    private let handle: UnsafeMutableRawPointer

    public init(view: AvatarRepositoryMetalView, width: Int, height: Int, modelData: Data? = nil) throws {
        guard let handle = AvatarRepositoryEngineBridge.create(
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
        AvatarRepositoryEngineBridge.destroy(handle)
    }

    public func resize(width: Int, height: Int) throws {
        guard AvatarRepositoryEngineBridge.resize(withHandle: handle, width: width, height: height) else {
            throw AvatarEngineError.nativeCallFailed("repository.resize")
        }
    }

    public func setParamsJSON(_ json: String) throws {
        guard AvatarRepositoryEngineBridge.setParamsJSON(json, handle: handle) else {
            throw AvatarEngineError.nativeCallFailed("repository.setParamsJSON")
        }
    }

    public func equipItem(_ itemID: String) throws {
        guard AvatarRepositoryEngineBridge.equipItem(itemID, handle: handle) else {
            throw AvatarEngineError.nativeCallFailed("repository.equipItem")
        }
    }

    public func setMorph(_ target: MorphTarget, _ value: Float) throws {
        guard AvatarRepositoryEngineBridge.setMorph(target.rawValue, value: value, handle: handle) else {
            throw AvatarEngineError.nativeCallFailed("repository.setMorph")
        }
    }

    public func playEmotion(_ id: String) throws {
        guard AvatarRepositoryEngineBridge.playEmotion(id, handle: handle) else {
            throw AvatarEngineError.nativeCallFailed("repository.playEmotion")
        }
    }

    public func setRotation(yaw: Float, pitch: Float) throws {
        guard AvatarRepositoryEngineBridge.setRotationYaw(yaw, pitch: pitch, handle: handle) else {
            throw AvatarEngineError.nativeCallFailed("repository.setRotation")
        }
    }

    public func addRotation(yawDelta: Float, pitchDelta: Float) throws {
        guard AvatarRepositoryEngineBridge.addRotationYaw(yawDelta, pitch: pitchDelta, handle: handle) else {
            throw AvatarEngineError.nativeCallFailed("repository.addRotation")
        }
    }

    public func setAutomaticRotation(enabled: Bool, speed: Float) throws {
        guard AvatarRepositoryEngineBridge.setAutomaticRotationEnabled(enabled, speed: speed, handle: handle) else {
            throw AvatarEngineError.nativeCallFailed("repository.setAutomaticRotation")
        }
    }

    public func render() throws {
        guard AvatarRepositoryEngineBridge.renderFrame(withHandle: handle) else {
            throw AvatarEngineError.nativeCallFailed("repository.renderFrame")
        }
    }

    public func render(at timestamp: CFTimeInterval) throws {
        guard AvatarRepositoryEngineBridge.renderFrame(withHandle: handle, timestamp: timestamp) else {
            throw AvatarEngineError.nativeCallFailed("repository.renderFrame")
        }
    }
}
#endif
