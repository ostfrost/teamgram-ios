#import "AvatarNativeEngineAdapter.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <os/log.h>

#if __has_include(<filament/Engine.h>) && !defined(AVATAR_DISABLE_FILAMENT)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshorten-64-to-32"
#include <filament/Box.h>
#include <filament/Camera.h>
#include <filament/Color.h>
#include <filament/Engine.h>
#include <filament/IndexBuffer.h>
#include <filament/IndirectLight.h>
#include <filament/LightManager.h>
#include <filament/Material.h>
#include <filament/Renderer.h>
#include <filament/RenderableManager.h>
#include <filament/Scene.h>
#include <filament/SwapChain.h>
#include <filament/TransformManager.h>
#include <filament/VertexBuffer.h>
#include <filament/View.h>
#include <filament/Viewport.h>
#include <filamat/MaterialBuilder.h>
#include <gltfio/AssetLoader.h>
#include <gltfio/Animator.h>
#include <gltfio/FilamentAsset.h>
#include <gltfio/FilamentInstance.h>
#include <gltfio/MaterialProvider.h>
#include <gltfio/ResourceLoader.h>
#include <gltfio/TextureProvider.h>
#include <gltfio/materials/uberarchive.h>
#include <math/mat4.h>
#include <math/vec3.h>
#include <utils/Entity.h>
#include <utils/EntityManager.h>
#pragma clang diagnostic pop
#endif

#define AVATAR_LOG(fmt, ...) os_log(OS_LOG_DEFAULT, "AvatarIntegration: " fmt, ##__VA_ARGS__)

namespace {

#if __has_include(<filament/Engine.h>) && !defined(AVATAR_DISABLE_FILAMENT)
struct TriangleVertex {
    float position[3];
    uint32_t color;
};

constexpr TriangleVertex kTriangleVertices[] = {
    {{ 0.0f,  0.82f,  0.0f}, 0xff34d399u},
    {{-0.78f, -0.48f,  0.46f}, 0xff34d399u},
    {{ 0.78f, -0.48f,  0.46f}, 0xff34d399u},

    {{ 0.0f,  0.82f,  0.0f}, 0xff60a5fau},
    {{ 0.78f, -0.48f,  0.46f}, 0xff60a5fau},
    {{ 0.0f, -0.48f, -0.72f}, 0xff60a5fau},

    {{ 0.0f,  0.82f,  0.0f}, 0xfff472b6u},
    {{ 0.0f, -0.48f, -0.72f}, 0xfff472b6u},
    {{-0.78f, -0.48f,  0.46f}, 0xfff472b6u},

    {{-0.78f, -0.48f,  0.46f}, 0xfffbbf24u},
    {{ 0.0f, -0.48f, -0.72f}, 0xfffbbf24u},
    {{ 0.78f, -0.48f,  0.46f}, 0xfffbbf24u}
};

constexpr uint16_t kTriangleIndices[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11};

constexpr char kTriangleMaterialSource[] =
    "void material(inout MaterialInputs material) {"
    "  prepareMaterial(material);"
    "  material.baseColor = getColor();"
    "}";

constexpr double kMaximumAutomaticRotationStep = 1.0 / 30.0;

filament::Engine::Config makeEngineConfig() {
    filament::Engine::Config config;
    config.commandBufferSizeMB = 1;
    config.minCommandBufferSizeMB = 1;
    config.perRenderPassArenaSizeMB = 2;
    config.perFrameCommandsSizeMB = 1;
    config.jobSystemThreadCount = 1;
    config.metalUploadBufferSizeBytes = 0;
    config.materialCacheCapacity = 0;
    config.programCacheCapacity = 0;
    config.disableParallelShaderCompile = true;
    return config;
}
#endif

} // namespace

AvatarNativeEngineAdapter::AvatarNativeEngineAdapter(CALayer *layer, NSInteger width, NSInteger height, NSData *modelData)
    : layer_(layer),
      width_(width),
      height_(height),
      modelData_(modelData) {
}

AvatarNativeEngineAdapter::~AvatarNativeEngineAdapter() {
    destroyRenderer();
}

bool AvatarNativeEngineAdapter::resize(NSInteger width, NSInteger height) {
    if (width <= 0 || height <= 0) {
        return false;
    }
    width_ = width;
    height_ = height;
    viewportDirty_ = true; // Откладываем пересчет вьюпорта до фазы рендеринга
    return true;
}

bool AvatarNativeEngineAdapter::setParamsJSON(const std::string &json) {
    paramsJson_ = json;
    return true;
}

bool AvatarNativeEngineAdapter::equipItem(const std::string &itemId) {
    return !itemId.empty();
}

bool AvatarNativeEngineAdapter::setMorph(const std::string &target, float value) {
    return !target.empty() && std::isfinite(value);
}

bool AvatarNativeEngineAdapter::playEmotion(const std::string &emotionId) {
    return !emotionId.empty();
}

bool AvatarNativeEngineAdapter::setRotation(float yaw, float pitch) {
    if (!std::isfinite(yaw) || !std::isfinite(pitch)) {
        return false;
    }
    yaw_ = yaw;
    pitch_ = std::max(-1.2f, std::min(1.2f, pitch));
    transformDirty_ = true;
    lastRenderedTimestamp_ = 0.0;
    return true;
}

bool AvatarNativeEngineAdapter::addRotation(float yawDelta, float pitchDelta) {
    if (!std::isfinite(yawDelta) || !std::isfinite(pitchDelta)) {
        return false;
    }
    yaw_ += yawDelta;
    pitch_ = std::max(-1.2f, std::min(1.2f, pitch_ + pitchDelta));
    transformDirty_ = true;
    lastRenderedTimestamp_ = 0.0;
    return true;
}

bool AvatarNativeEngineAdapter::renderFrame() {
    return renderFrame(0.0);
}

bool AvatarNativeEngineAdapter::setAutomaticRotation(bool enabled, float speed) {
    if (!std::isfinite(speed)) {
        return false;
    }
    automaticRotationEnabled_ = enabled && speed != 0.0f;
    automaticRotationSpeed_ = speed;
    lastRenderedTimestamp_ = 0.0;
    return true;
}

bool AvatarNativeEngineAdapter::renderFrame(double timestamp) {
#if __has_include(<filament/Engine.h>) && !defined(AVATAR_DISABLE_FILAMENT)
    if (layer_ == nil || width_ <= 0 || height_ <= 0) {
        return false;
    }
    if (!initializeRenderer()) {
        return false;
    }

    // Применяем изменения матриц и размеров только при необходимости
    if (viewportDirty_) {
        updateViewport();
        viewportDirty_ = false;
    }

    if (!renderer_->beginFrame(swapChain_)) {
        return true;
    }

    advanceAutomaticRotation(timestamp);

    if (transformDirty_) {
        updateContentTransform();
        transformDirty_ = false;
    }

    if (isAnimated_) {
        updateGltfSkinning();
    }
    
    renderer_->render(view_);
    renderer_->endFrame();
    
    if (!didLogFirstFrame_) {
        didLogFirstFrame_ = true;
        AVATAR_LOG("rendered first Filament frame");
    }
    return true;
#else
    return false;
#endif
}

bool AvatarNativeEngineAdapter::initializeRenderer() {
#if __has_include(<filament/Engine.h>) && !defined(AVATAR_DISABLE_FILAMENT)
    if (engine_ != nullptr) {
        return renderer_ != nullptr && swapChain_ != nullptr && view_ != nullptr && scene_ != nullptr;
    }

    constexpr filament::Engine::Backend backend = filament::Engine::Backend::METAL;
    filament::Engine::Config config = makeEngineConfig();
    engine_ = filament::Engine::Builder()
        .backend(backend)
        .config(&config)
        .build();

    if (engine_ == nullptr) {
        AVATAR_LOG("Filament Engine::create returned null");
        return false;
    }

    swapChain_ = engine_->createSwapChain((__bridge void *)layer_);
    renderer_ = engine_->createRenderer();
    view_ = engine_->createView();
    scene_ = engine_->createScene();
    
    cameraEntity_ = utils::EntityManager::get().create();
    camera_ = engine_->createCamera(cameraEntity_);

    if (swapChain_ == nullptr || renderer_ == nullptr || view_ == nullptr || scene_ == nullptr || camera_ == nullptr) {
        AVATAR_LOG("Filament object creation failed swap=%p renderer=%p view=%p scene=%p camera=%p", swapChain_, renderer_, view_, scene_, camera_);
        destroyRenderer();
        return false;
    }

    filament::Renderer::ClearOptions clearOptions;
    clearOptions.clear = true;
    clearOptions.discard = true;
    clearOptions.clearColor = filament::LinearColorA{0.02f, 0.025f, 0.03f, 1.0f};
    renderer_->setClearOptions(clearOptions);

    view_->setScene(scene_);
    view_->setCamera(camera_);
    view_->setPostProcessingEnabled(false);
    
    updateViewport();
    viewportDirty_ = false;
    ensureLighting();
    
    return initializeContent();
#else
    return false;
#endif
}

bool AvatarNativeEngineAdapter::initializeContent() {
#if __has_include(<filament/Engine.h>) && !defined(AVATAR_DISABLE_FILAMENT)
    if (modelData_ != nil && modelData_.length > 0) {
        return initializeGltfModel();
    }
    return initializeTriangle();
#else
    return false;
#endif
}

bool AvatarNativeEngineAdapter::initializeGltfModel() {
#if __has_include(<gltfio/AssetLoader.h>) && !defined(AVATAR_DISABLE_FILAMENT)
    if (gltfAsset_ != nullptr) {
        return true;
    }
    if (engine_ == nullptr || scene_ == nullptr || modelData_ == nil || modelData_.length == 0) {
        return false;
    }

    gltfMaterialProvider_ = filament::gltfio::createUbershaderProvider(
        engine_, UBERARCHIVE_DEFAULT_DATA, UBERARCHIVE_DEFAULT_SIZE
    );
    if (gltfMaterialProvider_ == nullptr) {
        AVATAR_LOG("glTF material provider creation failed");
        destroyRenderer();
        return false;
    }

    gltfAssetLoader_ = filament::gltfio::AssetLoader::create({engine_, gltfMaterialProvider_});
    if (gltfAssetLoader_ == nullptr) {
        AVATAR_LOG("glTF asset loader creation failed");
        destroyRenderer();
        return false;
    }

    gltfAsset_ = gltfAssetLoader_->createAsset(
        static_cast<const uint8_t*>(modelData_.bytes),
        static_cast<uint32_t>(modelData_.length)
    );
    
    if (gltfAsset_ == nullptr) {
        AVATAR_LOG("glTF asset creation failed for %lu bytes", (unsigned long)modelData_.length);
        destroyRenderer();
        return false;
    }

    std::unique_ptr<filament::gltfio::TextureProvider> stbProvider(filament::gltfio::createStbProvider(engine_));
    std::unique_ptr<filament::gltfio::TextureProvider> ktxProvider(filament::gltfio::createKtx2Provider(engine_));
    filament::gltfio::ResourceLoader resourceLoader({engine_, nullptr, true});
    
    if (stbProvider != nullptr) {
        resourceLoader.addTextureProvider("image/png", stbProvider.get());
        resourceLoader.addTextureProvider("image/jpeg", stbProvider.get());
    }
    if (ktxProvider != nullptr) {
        resourceLoader.addTextureProvider("image/ktx2", ktxProvider.get());
    }

    if (!resourceLoader.loadResources(gltfAsset_)) {
        AVATAR_LOG("glTF resource loading failed");
        destroyRenderer();
        return false;
    }

    resourceLoader.evictResourceData();
    gltfAsset_->releaseSourceData();
    
    modelData_ = nil; // Zero-copy cleanup

    scene_->addEntities(gltfAsset_->getEntities(), gltfAsset_->getEntityCount());
    configureGltfRenderables();

    const filament::Aabb bounds = gltfAsset_->getBoundingBox();
    if (!bounds.isEmpty()) {
        const filament::math::float3 center = bounds.center();
        const filament::math::float3 extent = bounds.extent();
        modelCenter_[0] = center.x;
        modelCenter_[1] = center.y;
        modelCenter_[2] = center.z;

        const float radius = std::max(0.001f, length(extent));
        modelScale_ = 1.35f / radius;
    } else {
        modelCenter_[0] = 0.0f;
        modelCenter_[1] = 0.0f;
        modelCenter_[2] = 0.0f;
        modelScale_ = 1.0f;
    }

    updateGltfTransform();
    transformDirty_ = false;
    
    const auto *instance = gltfAsset_->getInstance();
    const size_t skinCount = instance != nullptr ? instance->getSkinCount() : 0;
    
    if (skinCount > 0) {
        updateGltfSkinning();
    }
    
    AVATAR_LOG("initialized glTF model with %zu entities, %zu renderables, %zu skins, center=(%.3f, %.3f, %.3f), scale=%.3f",
        gltfAsset_->getEntityCount(), gltfAsset_->getRenderableEntityCount(), skinCount,
        modelCenter_[0], modelCenter_[1], modelCenter_[2], modelScale_);
    return true;
#else
    return false;
#endif
}

bool AvatarNativeEngineAdapter::initializeTriangle() {
#if __has_include(<filament/Engine.h>) && !defined(AVATAR_DISABLE_FILAMENT)
    if (!triangleEntity_.isNull()) {
        return vertexBuffer_ != nullptr && indexBuffer_ != nullptr && material_ != nullptr;
    }
    if (engine_ == nullptr || scene_ == nullptr) {
        return false;
    }

    vertexBuffer_ = filament::VertexBuffer::Builder()
        .vertexCount(12)
        .bufferCount(1)
        .attribute(filament::VertexAttribute::POSITION, 0, filament::VertexBuffer::AttributeType::FLOAT3, 0, sizeof(TriangleVertex))
        .attribute(filament::VertexAttribute::COLOR, 0, filament::VertexBuffer::AttributeType::UBYTE4, offsetof(TriangleVertex, color), sizeof(TriangleVertex))
        .normalized(filament::VertexAttribute::COLOR)
        .build(*engine_);
        
    indexBuffer_ = filament::IndexBuffer::Builder()
        .indexCount(12)
        .bufferType(filament::IndexBuffer::IndexType::USHORT)
        .build(*engine_);

    if (vertexBuffer_ == nullptr || indexBuffer_ == nullptr) {
        AVATAR_LOG("Filament buffer creation failed vertex=%p index=%p", vertexBuffer_, indexBuffer_);
        destroyRenderer();
        return false;
    }

    vertexBuffer_->setBufferAt(*engine_, 0, filament::VertexBuffer::BufferDescriptor(kTriangleVertices, sizeof(kTriangleVertices), nullptr));
    indexBuffer_->setBuffer(*engine_, filament::IndexBuffer::BufferDescriptor(kTriangleIndices, sizeof(kTriangleIndices), nullptr));

    filamat::MaterialBuilder::init();
    filamat::Package package = filamat::MaterialBuilder()
        .name("Avatar hello triangle")
        .shading(filamat::MaterialBuilder::Shading::UNLIT)
        .require(filament::VertexAttribute::COLOR)
        .material(kTriangleMaterialSource)
        .targetApi(filamat::MaterialBuilder::TargetApi::METAL)
        .platform(filamat::MaterialBuilder::Platform::MOBILE)
        .build(engine_->getJobSystem());
    filamat::MaterialBuilder::shutdown();

    if (!package.isValid()) {
        AVATAR_LOG("Filament material package is invalid");
        destroyRenderer();
        return false;
    }

    material_ = filament::Material::Builder().package(package.getData(), package.getSize()).build(*engine_);
    if (material_ == nullptr) {
        AVATAR_LOG("Filament material creation failed");
        destroyRenderer();
        return false;
    }

    triangleEntity_ = utils::EntityManager::get().create();
    filament::RenderableManager::Builder(1)
        .boundingBox({{-1.0f, -1.0f, -1.0f}, {1.0f, 1.0f, 1.0f}})
        .material(0, material_->getDefaultInstance())
        .geometry(0, filament::RenderableManager::PrimitiveType::TRIANGLES, vertexBuffer_, indexBuffer_, 0, 12)
        .culling(false)
        .receiveShadows(false)
        .castShadows(false)
        .build(*engine_, triangleEntity_);
        
    scene_->addEntity(triangleEntity_);
    updateTriangleTransform();
    transformDirty_ = false;
    
    AVATAR_LOG("initialized Filament 3D triangle");

    return true;
#else
    return false;
#endif
}

void AvatarNativeEngineAdapter::updateContentTransform() {
#if __has_include(<filament/TransformManager.h>) && !defined(AVATAR_DISABLE_FILAMENT)
    if (gltfAsset_ != nullptr) {
        updateGltfTransform();
    } else {
        updateTriangleTransform();
    }
#endif
}

void AvatarNativeEngineAdapter::updateGltfTransform() {
#if __has_include(<gltfio/FilamentAsset.h>) && !defined(AVATAR_DISABLE_FILAMENT)
    if (engine_ == nullptr || gltfAsset_ == nullptr) return;

    auto &transformManager = engine_->getTransformManager();
    auto instance = transformManager.getInstance(gltfAsset_->getRoot());
    if (!instance) return;

    const filament::math::float3 center{modelCenter_[0], modelCenter_[1], modelCenter_[2]};
    const filament::math::mat4f transform =
        filament::math::mat4f::rotation(yaw_, filament::math::float3{0.0f, 1.0f, 0.0f}) *
        filament::math::mat4f::rotation(pitch_, filament::math::float3{1.0f, 0.0f, 0.0f}) *
        filament::math::mat4f::scaling(modelScale_) *
        filament::math::mat4f::translation(-center);
    transformManager.setTransform(instance, transform);
#endif
}

void AvatarNativeEngineAdapter::updateGltfSkinning() {
#if __has_include(<gltfio/FilamentInstance.h>) && !defined(AVATAR_DISABLE_FILAMENT)
    if (gltfAsset_ == nullptr) return;

    auto *instance = gltfAsset_->getInstance();
    if (instance == nullptr) return;

    auto *animator = instance->getAnimator();
    if (animator != nullptr) {
        animator->updateBoneMatrices();
    }
#endif
}

void AvatarNativeEngineAdapter::configureGltfRenderables() {
#if __has_include(<gltfio/FilamentAsset.h>) && !defined(AVATAR_DISABLE_FILAMENT)
    if (engine_ == nullptr || gltfAsset_ == nullptr) return;

    auto &renderableManager = engine_->getRenderableManager();
    const auto *renderables = gltfAsset_->getRenderableEntities();
    const size_t renderableCount = gltfAsset_->getRenderableEntityCount();
    for (size_t i = 0; i < renderableCount; ++i) {
        auto instance = renderableManager.getInstance(renderables[i]);
        if (instance) {
            renderableManager.setCulling(instance, false);
            renderableManager.setCastShadows(instance, false);
            renderableManager.setReceiveShadows(instance, false);
        }
    }
#endif
}

void AvatarNativeEngineAdapter::updateTriangleTransform() {
#if __has_include(<filament/TransformManager.h>) && !defined(AVATAR_DISABLE_FILAMENT)
    if (engine_ == nullptr || triangleEntity_.isNull()) return;

    auto &transformManager = engine_->getTransformManager();
    auto instance = transformManager.getInstance(triangleEntity_);
    if (!instance) return;

    const filament::math::mat4f transform =
        filament::math::mat4f::rotation(yaw_, filament::math::float3{0.0f, 1.0f, 0.0f}) *
        filament::math::mat4f::rotation(pitch_, filament::math::float3{1.0f, 0.0f, 0.0f});
    transformManager.setTransform(instance, transform);
#endif
}

void AvatarNativeEngineAdapter::advanceAutomaticRotation(double timestamp) {
#if __has_include(<filament/Engine.h>) && !defined(AVATAR_DISABLE_FILAMENT)
    if (!automaticRotationEnabled_) {
        lastRenderedTimestamp_ = 0.0;
        return;
    }

    if (timestamp <= 0.0 || !std::isfinite(timestamp)) {
        yaw_ += automaticRotationSpeed_ * (1.0f / 60.0f);
        transformDirty_ = true;
        return;
    }

    if (lastRenderedTimestamp_ <= 0.0) {
        lastRenderedTimestamp_ = timestamp;
        return;
    }

    const double elapsed = std::min(
        std::max(timestamp - lastRenderedTimestamp_, 0.0),
        kMaximumAutomaticRotationStep
    );
    lastRenderedTimestamp_ = timestamp;

    if (elapsed <= 0.0) {
        return;
    }

    yaw_ += static_cast<float>(elapsed) * automaticRotationSpeed_;
    transformDirty_ = true;
#endif
}

void AvatarNativeEngineAdapter::ensureLighting() {
#if __has_include(<filament/LightManager.h>) && !defined(AVATAR_DISABLE_FILAMENT)
    if (engine_ == nullptr || scene_ == nullptr || !lightEntity_.isNull()) return;

    const filament::math::float3 ambientIrradiance[] = {{1.0f, 1.0f, 1.0f}};
    indirectLight_ = filament::IndirectLight::Builder()
        .irradiance(1, ambientIrradiance)
        .intensity(25000.0f)
        .build(*engine_);
    if (indirectLight_ != nullptr) {
        scene_->setIndirectLight(indirectLight_);
    }

    lightEntity_ = utils::EntityManager::get().create();
    if (filament::LightManager::Builder(filament::LightManager::Type::DIRECTIONAL)
            .direction({0.0f, -0.35f, -1.0f})
            .intensity(110000.0f)
            .castShadows(false)
            .build(*engine_, lightEntity_) == filament::LightManager::Builder::Success) {
        scene_->addEntity(lightEntity_);
    } else {
        utils::EntityManager::get().destroy(lightEntity_);
        lightEntity_ = utils::Entity();
    }
#endif
}

void AvatarNativeEngineAdapter::destroyRenderer() {
#if __has_include(<filament/Engine.h>) && !defined(AVATAR_DISABLE_FILAMENT)
    if (engine_ == nullptr) return;

    auto safeDestroy = [this](auto*& ptr) {
        if (ptr) { this->engine_->destroy(ptr); ptr = nullptr; }
    };

    if (!triangleEntity_.isNull()) {
        if (scene_ != nullptr) scene_->remove(triangleEntity_);
        engine_->destroy(triangleEntity_);
        utils::EntityManager::get().destroy(triangleEntity_);
        triangleEntity_ = utils::Entity();
    }

    if (gltfAsset_ != nullptr) {
        if (scene_ != nullptr) {
            scene_->removeEntities(gltfAsset_->getEntities(), gltfAsset_->getEntityCount());
        }
        if (gltfAssetLoader_ != nullptr) {
            gltfAssetLoader_->destroyAsset(gltfAsset_);
        }
        gltfAsset_ = nullptr;
    }

    if (gltfAssetLoader_ != nullptr) {
        filament::gltfio::AssetLoader::destroy(&gltfAssetLoader_);
        gltfAssetLoader_ = nullptr;
    }

    if (gltfMaterialProvider_ != nullptr) {
        gltfMaterialProvider_->destroyMaterials();
        delete gltfMaterialProvider_;
        gltfMaterialProvider_ = nullptr;
    }

    safeDestroy(material_);
    safeDestroy(indexBuffer_);
    safeDestroy(vertexBuffer_);
    
    if (indirectLight_ != nullptr) {
        if (scene_ != nullptr) scene_->setIndirectLight(nullptr);
        safeDestroy(indirectLight_);
    }

    if (!lightEntity_.isNull()) {
        if (scene_ != nullptr) scene_->remove(lightEntity_);
        engine_->destroy(lightEntity_);
        utils::EntityManager::get().destroy(lightEntity_);
        lightEntity_ = utils::Entity();
    }

    if (view_ != nullptr) {
        view_->setScene(nullptr);
        view_->setCamera(nullptr);
        safeDestroy(view_);
    }

    safeDestroy(scene_);
    safeDestroy(renderer_);

    if (!cameraEntity_.isNull()) {
        engine_->destroyCameraComponent(cameraEntity_);
        utils::EntityManager::get().destroy(cameraEntity_);
        cameraEntity_ = utils::Entity();
        camera_ = nullptr;
    }

    safeDestroy(swapChain_);

    engine_->flushAndWait();
    filament::Engine::destroy(&engine_);
#endif
}

void AvatarNativeEngineAdapter::updateViewport() {
#if __has_include(<filament/View.h>) && !defined(AVATAR_DISABLE_FILAMENT)
    if (view_ == nullptr) return;
    
    const uint32_t viewportWidth = static_cast<uint32_t>(std::max<NSInteger>(1, width_));
    const uint32_t viewportHeight = static_cast<uint32_t>(std::max<NSInteger>(1, height_));
    
    view_->setViewport(filament::Viewport{0, 0, viewportWidth, viewportHeight});
    
    if (camera_ != nullptr) {
        const double aspect = static_cast<double>(viewportWidth) / static_cast<double>(viewportHeight);
        camera_->setProjection(45.0, aspect, 0.1, 10.0, filament::Camera::Fov::VERTICAL);
        camera_->lookAt({0.0, 0.0, 3.2}, {0.0, 0.0, 0.0}, {0.0, 1.0, 0.0});
    }
#endif
}
