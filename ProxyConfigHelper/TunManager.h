//
//  TunManager.h
//  com.west2online.ClashX.ProxyConfigHelper
//
//  Creates utun devices for the main app. The helper runs as root, which
//  is required to open a utun control socket and to modify the routing
//  table; the resulting file descriptor is handed back over XPC so the
//  in-process clash core can drive the interface without privileges.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TunManager : NSObject

// inet4Address: CIDR form, e.g. @"198.18.0.1/30" (must match the core's tun inet4-address)
// inet6Address: CIDR form, e.g. @"fdfe:dcba:9876::1/126", or nil to skip IPv6
// On success returns the tun fd via fileHandle and the interface name (e.g. "utun5").
+ (void)startTunWithInet4Address:(NSString *)inet4Address
                    inet6Address:(nullable NSString *)inet6Address
                             mtu:(int)mtu
                           reply:(void (^)(NSFileHandle *_Nullable fileHandle,
                                           NSString *_Nullable interfaceName,
                                           NSString *_Nullable error))reply;

@end

NS_ASSUME_NONNULL_END
