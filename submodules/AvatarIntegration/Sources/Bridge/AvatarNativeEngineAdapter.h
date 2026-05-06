#pragma once

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

#include <string>

#if __has_include(<utils/Entity.h>) && !defined(AVATAR_DISABLE_FILAMENT)
#include <utils/Entity.h>
#else
namespace utils { class Entity { uint32_t id = 0; }; }
#endif

namespace filament {
class Camera;
class Engine;
class IndexBuffer;
class IndirectLight;
class Material;
class Renderer;
class Scene;
class SwapChain;
class VertexBuffer;
class View;
} // namespace filament

namespace filament::gltfio {
class AssetLoader;
class FilamentAsset;
class MaterialProvider;
} // namespace filament::gltfio

class AvatarNativeEngineAdapter {
public:
    AvatarNativeEngineAdapter(CALayer *layer, NSInteger width, NSInteger height, NSData *modelData);
    ~AvatarNativeEngineAdapter();

    AvatarNativeEngineAdapter(const AvatarNativeEngineAdapter &) = delete;
    AvatarNativeEngineAdapter &operator=(const AvatarNativeEngineAdapter &) = delete;

    bool resize(NSInteger width, NSInteger height);
    bool setParamsJSON(const std::string &json);
    bool equipItem(const std::string &itemId);
    bool setMorph(const std::string &target, float value);
    bool playEmotion(const std::string &emotionId);
    bool setRotation(float yaw, float pitch);
    bool addRotation(float yawDelta, float pitchDelta);
    bool setAutomaticRotation(bool enabled, float speed);
    bool renderFrame();
    bool renderFrame(double timestamp);

private:
    bool initializeRenderer();
    bool initializeContent();
    bool initializeGltfModel();
    bool initializeTriangle();
    void updateContentTransform();
    void updateGltfTransform();
    void updateGltfSkinning();
    void configureGltfRenderables();
    void updateTriangleTransform();
    void advanceAutomaticRotation(double timestamp);
    void ensureLighting();
    void destroyRenderer();
    void updateViewport();

    CALayer *layer_ = nil;
    NSInteger width_ = 0;
    NSInteger height_ = 0;
    
    NSData *modelData_ = nil;
    std::string paramsJson_;
    
    filament::Engine *engine_ = nullptr;
    filament::Renderer *renderer_ = nullptr;
    filament::SwapChain *swapChain_ = nullptr;
    filament::View *view_ = nullptr;
    filament::Scene *scene_ = nullptr;
    filament::Camera *camera_ = nullptr;
    filament::IndirectLight *indirectLight_ = nullptr;
    filament::gltfio::MaterialProvider *gltfMaterialProvider_ = nullptr;
    filament::gltfio::AssetLoader *gltfAssetLoader_ = nullptr;
    filament::gltfio::FilamentAsset *gltfAsset_ = nullptr;
    filament::VertexBuffer *vertexBuffer_ = nullptr;
    filament::IndexBuffer *indexBuffer_ = nullptr;
    filament::Material *material_ = nullptr;
    
    utils::Entity cameraEntity_;
    utils::Entity lightEntity_;
    utils::Entity triangleEntity_;
    
    float yaw_ = 0.7f;
    float pitch_ = -0.25f;
    float modelScale_ = 1.0f;
    float modelCenter_[3] = {0.0f, 0.0f, 0.0f};
    
    bool didLogFirstFrame_ = false;
    bool transformDirty_ = true;
    bool viewportDirty_ = true;
    bool isAnimated_ = false;
    bool automaticRotationEnabled_ = false;
    float automaticRotationSpeed_ = 0.0f;
    double lastRenderedTimestamp_ = 0.0;
};
