#import <AvatarEngineBridge/AvatarRepositoryEngineBridge.h>
#import <Metal/Metal.h>

#if __has_include(<CAvatarEngine/avatar_bridge.h>)
#import <CAvatarEngine/avatar_bridge.h>
#else
#import "avatar_bridge.h"
#endif

#include <TargetConditionals.h>
#include <algorithm>
#include <cmath>

extern "C" void avatar_engine_set_debug_orbit(AvatarEngine *engine, float yaw, float pitch);

namespace {

struct RepositoryAvatarHandle {
    AvatarEngine *engine = nullptr;
    float yaw = 0.0f;
    float pitch = 0.0f;
    bool automaticRotationEnabled = false;
    float automaticRotationSpeed = 0.0f;
    double lastRenderedTimestamp = 0.0;
};

constexpr double kMaximumAutomaticRotationStep = 1.0 / 30.0;

bool isValidHandle(void *handle) {
    return handle != nullptr && static_cast<RepositoryAvatarHandle *>(handle)->engine != nullptr;
}

RepositoryAvatarHandle *handleFromRaw(void *handle) {
    return static_cast<RepositoryAvatarHandle *>(handle);
}

bool isOK(AvatarErrorCode errorCode) {
    return errorCode == AVATAR_OK;
}

bool morphTargetFromString(NSString *target, MorphTarget *outTarget) {
    if (target == nil || outTarget == nullptr) {
        return false;
    }

    static NSDictionary<NSString *, NSNumber *> *mapping;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mapping = @{
            @"face_shape": @(MORPH_FACE_SHAPE),
            @"jaw_width": @(MORPH_JAW_WIDTH),
            @"cheek_fullness": @(MORPH_CHEEK_FULLNESS),
            @"chin_length": @(MORPH_CHIN_LENGTH),
            @"eye_size": @(MORPH_EYE_SIZE),
            @"eye_spacing": @(MORPH_EYE_SPACING)
        };
    });

    NSNumber *value = mapping[target];
    if (value == nil) {
        return false;
    }
    *outTarget = static_cast<MorphTarget>(value.intValue);
    return true;
}

} // namespace

@implementation AvatarRepositoryEngineBridge

+ (Class)renderLayerClass {
    return [CAMetalLayer class];
}

+ (void)configureRenderLayer:(CALayer *)layer screenScale:(CGFloat)screenScale {
    layer.opaque = YES;
    layer.contentsScale = screenScale;

    if ([layer isKindOfClass:[CAMetalLayer class]]) {
        CAMetalLayer *metalLayer = (CAMetalLayer *)layer;
        metalLayer.opaque = YES;
        metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        metalLayer.framebufferOnly = YES;
    }
}

+ (void)updateRenderLayer:(CALayer *)layer screenScale:(CGFloat)screenScale drawableSize:(CGSize)drawableSize {
    layer.contentsScale = screenScale;

    if ([layer isKindOfClass:[CAMetalLayer class]]) {
        ((CAMetalLayer *)layer).drawableSize = drawableSize;
    }
}

+ (void *)createWithLayer:(CALayer *)layer width:(NSInteger)width height:(NSInteger)height modelData:(NSData *)modelData {
    @try {
        if (![layer isKindOfClass:[CAMetalLayer class]] || width <= 0 || height <= 0) {
            return nullptr;
        }

        AvatarEngine *engine = avatar_engine_create((__bridge void *)layer, static_cast<int>(width), static_cast<int>(height));
        if (engine == nullptr) {
            return nullptr;
        }

        if (modelData.length > 0) {
            const uint8_t *bytes = static_cast<const uint8_t *>(modelData.bytes);
            if (!isOK(avatar_load_model_glb(engine, bytes, static_cast<size_t>(modelData.length)))) {
                avatar_engine_destroy(engine);
                return nullptr;
            }
        }

        auto *handle = new RepositoryAvatarHandle();
        handle->engine = engine;
        return handle;
    } @catch (NSException *) {
        return nullptr;
    }
}

+ (void)destroy:(void *)handle {
    @try {
        auto *repositoryHandle = handleFromRaw(handle);
        if (repositoryHandle != nullptr) {
            if (repositoryHandle->engine != nullptr) {
                avatar_engine_destroy(repositoryHandle->engine);
                repositoryHandle->engine = nullptr;
            }
            delete repositoryHandle;
        }
    } @catch (NSException *) {
    }
}

+ (BOOL)resizeWithHandle:(void *)handle width:(NSInteger)width height:(NSInteger)height {
    @try {
        if (!isValidHandle(handle) || width <= 0 || height <= 0) {
            return NO;
        }
        avatar_engine_resize(handleFromRaw(handle)->engine, static_cast<int>(width), static_cast<int>(height));
        return YES;
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)setParamsJSON:(NSString *)json handle:(void *)handle {
    @try {
        if (!isValidHandle(handle) || json == nil) {
            return NO;
        }
        return isOK(avatar_set_params_json(handleFromRaw(handle)->engine, [json UTF8String] ?: ""));
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)equipItem:(NSString *)itemId handle:(void *)handle {
    @try {
        if (!isValidHandle(handle) || itemId == nil) {
            return NO;
        }
        return isOK(avatar_equip_item(handleFromRaw(handle)->engine, [itemId UTF8String] ?: ""));
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)setMorph:(NSString *)target value:(float)value handle:(void *)handle {
    @try {
        MorphTarget morphTarget;
        if (!isValidHandle(handle) || !morphTargetFromString(target, &morphTarget)) {
            return NO;
        }
        return isOK(avatar_set_morph(handleFromRaw(handle)->engine, morphTarget, value));
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)playEmotion:(NSString *)emotionId handle:(void *)handle {
    @try {
        if (!isValidHandle(handle) || emotionId == nil) {
            return NO;
        }
        return isOK(avatar_play_emotion(handleFromRaw(handle)->engine, [emotionId UTF8String] ?: ""));
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)setRotationYaw:(float)yaw pitch:(float)pitch handle:(void *)handle {
    @try {
        if (!isValidHandle(handle)) {
            return NO;
        }
        auto *repositoryHandle = handleFromRaw(handle);
        repositoryHandle->yaw = yaw;
        repositoryHandle->pitch = std::max(-1.2f, std::min(1.2f, pitch));
        repositoryHandle->lastRenderedTimestamp = 0.0;
        avatar_engine_set_debug_orbit(repositoryHandle->engine, repositoryHandle->yaw, repositoryHandle->pitch);
        return YES;
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)addRotationYaw:(float)yawDelta pitch:(float)pitchDelta handle:(void *)handle {
    @try {
        if (!isValidHandle(handle)) {
            return NO;
        }
        auto *repositoryHandle = handleFromRaw(handle);
        repositoryHandle->yaw += yawDelta;
        repositoryHandle->pitch = std::max(-1.2f, std::min(1.2f, repositoryHandle->pitch + pitchDelta));
        repositoryHandle->lastRenderedTimestamp = 0.0;
        avatar_engine_set_debug_orbit(repositoryHandle->engine, repositoryHandle->yaw, repositoryHandle->pitch);
        return YES;
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)setAutomaticRotationEnabled:(BOOL)enabled speed:(float)speed handle:(void *)handle {
    @try {
        if (!isValidHandle(handle)) {
            return NO;
        }
        if (!std::isfinite(speed)) {
            return NO;
        }
        auto *repositoryHandle = handleFromRaw(handle);
        repositoryHandle->automaticRotationEnabled = enabled && speed != 0.0f;
        repositoryHandle->automaticRotationSpeed = speed;
        repositoryHandle->lastRenderedTimestamp = 0.0;
        return YES;
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)renderFrameWithHandle:(void *)handle {
    @try {
        if (!isValidHandle(handle)) {
            return NO;
        }
        avatar_engine_render_frame(handleFromRaw(handle)->engine);
        return YES;
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)renderFrameWithHandle:(void *)handle timestamp:(CFTimeInterval)timestamp {
    @try {
        if (!isValidHandle(handle)) {
            return NO;
        }
        auto *repositoryHandle = handleFromRaw(handle);
        if (repositoryHandle->automaticRotationEnabled && std::isfinite(timestamp) && timestamp > 0.0) {
            if (repositoryHandle->lastRenderedTimestamp > 0.0) {
                const double elapsed = std::min(
                    std::max(timestamp - repositoryHandle->lastRenderedTimestamp, 0.0),
                    kMaximumAutomaticRotationStep
                );
                if (elapsed > 0.0) {
                    repositoryHandle->yaw += static_cast<float>(elapsed) * repositoryHandle->automaticRotationSpeed;
                    avatar_engine_set_debug_orbit(repositoryHandle->engine, repositoryHandle->yaw, repositoryHandle->pitch);
                }
            }
            repositoryHandle->lastRenderedTimestamp = timestamp;
        }
        avatar_engine_render_frame(repositoryHandle->engine);
        return YES;
    } @catch (NSException *) {
        return NO;
    }
}

@end
