#define GLES_SILENCE_DEPRECATION 1

#import <AvatarEngineBridge/AvatarEngineBridge.h>
#import "AvatarNativeEngineAdapter.h"

#include <string>
#include <TargetConditionals.h>

namespace {

bool isValidHandle(void *handle) {
    return handle != nullptr;
}

AvatarNativeEngineAdapter *adapterFromHandle(void *handle) {
    return static_cast<AvatarNativeEngineAdapter *>(handle);
}

} // namespace

@implementation AvatarEngineBridge

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
        metalLayer.presentsWithTransaction = NO;
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
        try {
            return new AvatarNativeEngineAdapter(layer, width, height, modelData);
        } catch (...) {
            return nullptr;
        }
    } @catch (NSException *) {
        return nullptr;
    }
}

+ (void)destroy:(void *)handle {
    @try {
        try {
            delete adapterFromHandle(handle);
        } catch (...) {
        }
    } @catch (NSException *) {
    }
}

+ (BOOL)resizeWithHandle:(void *)handle width:(NSInteger)width height:(NSInteger)height {
    @try {
        try {
            return isValidHandle(handle) && adapterFromHandle(handle)->resize(width, height);
        } catch (...) {
            return NO;
        }
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)setParamsJSON:(NSString *)json handle:(void *)handle {
    @try {
        try {
            if (!isValidHandle(handle) || json == nil) {
                return NO;
            }
            return adapterFromHandle(handle)->setParamsJSON([json UTF8String] ?: "");
        } catch (...) {
            return NO;
        }
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)equipItem:(NSString *)itemId handle:(void *)handle {
    @try {
        try {
            if (!isValidHandle(handle) || itemId == nil) {
                return NO;
            }
            return adapterFromHandle(handle)->equipItem([itemId UTF8String] ?: "");
        } catch (...) {
            return NO;
        }
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)setMorph:(NSString *)target value:(float)value handle:(void *)handle {
    @try {
        try {
            if (!isValidHandle(handle) || target == nil) {
                return NO;
            }
            return adapterFromHandle(handle)->setMorph([target UTF8String] ?: "", value);
        } catch (...) {
            return NO;
        }
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)playEmotion:(NSString *)emotionId handle:(void *)handle {
    @try {
        try {
            if (!isValidHandle(handle) || emotionId == nil) {
                return NO;
            }
            return adapterFromHandle(handle)->playEmotion([emotionId UTF8String] ?: "");
        } catch (...) {
            return NO;
        }
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)setRotationYaw:(float)yaw pitch:(float)pitch handle:(void *)handle {
    @try {
        try {
            return isValidHandle(handle) && adapterFromHandle(handle)->setRotation(yaw, pitch);
        } catch (...) {
            return NO;
        }
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)addRotationYaw:(float)yawDelta pitch:(float)pitchDelta handle:(void *)handle {
    @try {
        try {
            return isValidHandle(handle) && adapterFromHandle(handle)->addRotation(yawDelta, pitchDelta);
        } catch (...) {
            return NO;
        }
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)setAutomaticRotationEnabled:(BOOL)enabled speed:(float)speed handle:(void *)handle {
    @try {
        try {
            return isValidHandle(handle) && adapterFromHandle(handle)->setAutomaticRotation(enabled, speed);
        } catch (...) {
            return NO;
        }
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)renderFrameWithHandle:(void *)handle {
    @try {
        try {
            return isValidHandle(handle) && adapterFromHandle(handle)->renderFrame();
        } catch (...) {
            return NO;
        }
    } @catch (NSException *) {
        return NO;
    }
}

+ (BOOL)renderFrameWithHandle:(void *)handle timestamp:(CFTimeInterval)timestamp {
    @try {
        try {
            return isValidHandle(handle) && adapterFromHandle(handle)->renderFrame(timestamp);
        } catch (...) {
            return NO;
        }
    } @catch (NSException *) {
        return NO;
    }
}

@end
