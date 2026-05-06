#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

@interface AvatarRepositoryEngineBridge : NSObject

+ (Class)renderLayerClass;
+ (void)configureRenderLayer:(CALayer *)layer screenScale:(CGFloat)screenScale;
+ (void)updateRenderLayer:(CALayer *)layer screenScale:(CGFloat)screenScale drawableSize:(CGSize)drawableSize;
+ (nullable void *)createWithLayer:(CALayer *)layer width:(NSInteger)width height:(NSInteger)height modelData:(nullable NSData *)modelData;
+ (void)destroy:(nullable void *)handle;
+ (BOOL)resizeWithHandle:(nullable void *)handle width:(NSInteger)width height:(NSInteger)height;
+ (BOOL)setParamsJSON:(NSString *)json handle:(nullable void *)handle;
+ (BOOL)equipItem:(NSString *)itemId handle:(nullable void *)handle;
+ (BOOL)setMorph:(NSString *)target value:(float)value handle:(nullable void *)handle;
+ (BOOL)playEmotion:(NSString *)emotionId handle:(nullable void *)handle;
+ (BOOL)setRotationYaw:(float)yaw pitch:(float)pitch handle:(nullable void *)handle;
+ (BOOL)addRotationYaw:(float)yawDelta pitch:(float)pitchDelta handle:(nullable void *)handle;
+ (BOOL)setAutomaticRotationEnabled:(BOOL)enabled speed:(float)speed handle:(nullable void *)handle;
+ (BOOL)renderFrameWithHandle:(nullable void *)handle;
+ (BOOL)renderFrameWithHandle:(nullable void *)handle timestamp:(CFTimeInterval)timestamp;

@end

NS_ASSUME_NONNULL_END
