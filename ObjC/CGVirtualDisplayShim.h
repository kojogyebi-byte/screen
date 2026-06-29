//
//  CGVirtualDisplayShim.h
//  ScreenExtend
//
//  Thin Objective-C wrapper around the private CoreGraphics virtual-display
//  API (CGVirtualDisplay / CGVirtualDisplayDescriptor / ...). These classes are
//  not part of the public SDK, so we resolve them at runtime via
//  NSClassFromString to avoid any link-time symbol requirements. This is the
//  same mechanism used by tools such as BetterDisplay and works on Apple
//  Silicon and Intel without a kernel extension or DriverKit driver.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface VirtualDisplayShim : NSObject

/// Creates a virtual display and returns its CGDirectDisplayID.
/// Returns 0 if the private API is unavailable or creation failed.
- (CGDirectDisplayID)createDisplayWithName:(NSString *)name
                                      width:(uint32_t)width
                                     height:(uint32_t)height
                                      hiDPI:(BOOL)hiDPI;

/// Tears down the virtual display (releases the underlying object).
- (void)destroyDisplay;

/// 0 when no display is active.
@property (nonatomic, readonly) CGDirectDisplayID displayID;

/// YES if the private CoreGraphics virtual-display classes were found.
+ (BOOL)isSupported;

@end

NS_ASSUME_NONNULL_END
