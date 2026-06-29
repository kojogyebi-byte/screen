//
//  CGVirtualDisplayShim.m
//  ScreenExtend
//

#import "CGVirtualDisplayShim.h"
#import <objc/runtime.h>

#pragma mark - Private API redeclarations
// We redeclare just enough of the private interface to get typed message
// sends. We NEVER reference the class symbols directly (e.g. [CGVirtualDisplay
// alloc]); every instance is created from a Class obtained via
// NSClassFromString, so the linker is never asked to resolve these symbols.

@interface _SE_CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(uint32_t)width
                       height:(uint32_t)height
                  refreshRate:(double)refreshRate;
@end

@interface _SE_CGVirtualDisplaySettings : NSObject
@property(nonatomic, assign) uint32_t hiDPI;
@property(nonatomic, retain) NSArray *modes;
@end

@interface _SE_CGVirtualDisplayDescriptor : NSObject
@property(nonatomic, retain) dispatch_queue_t queue;
@property(nonatomic, copy)   NSString *name;
@property(nonatomic, assign) uint32_t maxPixelsWide;
@property(nonatomic, assign) uint32_t maxPixelsHigh;
@property(nonatomic, assign) CGSize   sizeInMillimeters;
@property(nonatomic, assign) uint32_t productID;
@property(nonatomic, assign) uint32_t vendorID;
@property(nonatomic, assign) uint32_t serialNum;
@property(nonatomic, copy)   void (^terminationHandler)(id sender);
@end

@interface _SE_CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@property(nonatomic, readonly) CGDirectDisplayID displayID;
@end

#pragma mark -

@interface VirtualDisplayShim ()
@property(nonatomic, strong) id display;          // _SE_CGVirtualDisplay
@property(nonatomic, strong) dispatch_queue_t cbQueue;
@property(nonatomic, assign) CGDirectDisplayID displayID;
@end

@implementation VirtualDisplayShim

+ (BOOL)isSupported {
    return NSClassFromString(@"CGVirtualDisplayDescriptor") != nil
        && NSClassFromString(@"CGVirtualDisplaySettings")   != nil
        && NSClassFromString(@"CGVirtualDisplayMode")       != nil
        && NSClassFromString(@"CGVirtualDisplay")           != nil;
}

- (CGDirectDisplayID)createDisplayWithName:(NSString *)name
                                      width:(uint32_t)width
                                     height:(uint32_t)height
                                      hiDPI:(BOOL)hiDPI {
    [self destroyDisplay];

    Class descCls = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class setCls  = NSClassFromString(@"CGVirtualDisplaySettings");
    Class modeCls = NSClassFromString(@"CGVirtualDisplayMode");
    Class dispCls = NSClassFromString(@"CGVirtualDisplay");
    if (!descCls || !setCls || !modeCls || !dispCls) {
        NSLog(@"[ScreenExtend] Virtual display API unavailable on this macOS version.");
        return 0;
    }

    self.cbQueue = dispatch_queue_create("com.shamaapps.screenextend.vdisplay",
                                         DISPATCH_QUEUE_SERIAL);

    _SE_CGVirtualDisplayDescriptor *desc = [[descCls alloc] init];
    desc.queue = self.cbQueue;
    desc.name = name;
    desc.maxPixelsWide = width;
    desc.maxPixelsHigh = height;
    // ~120 dpi: 25.4mm per inch / 120 px-per-inch = 0.2117 mm per px
    desc.sizeInMillimeters = CGSizeMake((CGFloat)width * 0.2117,
                                        (CGFloat)height * 0.2117);
    desc.productID = 0x1357;
    desc.vendorID  = 0x2468;
    desc.serialNum = 0x0001;
    __weak typeof(self) weakSelf = self;
    desc.terminationHandler = ^(id sender) {
        NSLog(@"[ScreenExtend] Virtual display terminated by system.");
        weakSelf.displayID = 0;
    };

    _SE_CGVirtualDisplay *disp = [[dispCls alloc] initWithDescriptor:desc];
    if (!disp) {
        NSLog(@"[ScreenExtend] Failed to allocate virtual display.");
        return 0;
    }

    _SE_CGVirtualDisplayMode *mode =
        [[modeCls alloc] initWithWidth:width height:height refreshRate:60.0];

    _SE_CGVirtualDisplaySettings *settings = [[setCls alloc] init];
    settings.hiDPI = hiDPI ? 1 : 0;
    settings.modes = @[mode];

    BOOL ok = [disp applySettings:settings];
    if (!ok) {
        NSLog(@"[ScreenExtend] applySettings: failed.");
        return 0;
    }

    self.display = disp;
    self.displayID = disp.displayID;
    NSLog(@"[ScreenExtend] Virtual display created. id=%u (%ux%u hiDPI=%d)",
          self.displayID, width, height, hiDPI);
    return self.displayID;
}

- (void)destroyDisplay {
    self.display = nil;     // releasing the object removes the display
    self.cbQueue = nil;
    self.displayID = 0;
}

@end
