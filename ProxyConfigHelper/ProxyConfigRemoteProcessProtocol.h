//
//  ProxyConfigRemoteProcessProtocol.h
//  com.west2online.ClashX.ProxyConfigHelper
//
//  Created by yichengchen on 2019/8/17.
//  Copyright © 2019 west2online. All rights reserved.
//

@import Foundation;

typedef void(^stringReplyBlock)(NSString *);
typedef void(^boolReplyBlock)(BOOL);
typedef void(^dictReplyBlock)(NSDictionary *);
typedef void(^tunReplyBlock)(NSFileHandle *fileHandle, NSString *interfaceName, NSString *error);

@protocol ProxyConfigRemoteProcessProtocol <NSObject>
@required

- (void)getVersion:(stringReplyBlock)reply;

// Creates a utun device, assigns the given addresses, installs the
// all-IPv4/IPv6 sub-range routes through it, and replies with the tun
// file descriptor (fileHandle/interfaceName nil and error set on failure;
// inet6Address may be nil to skip IPv6). The interface lives as long as
// the fd stays open in the receiving process; the kernel purges the
// routes when it closes.
- (void)startTunWithInet4Address:(NSString *)inet4Address
                    inet6Address:(NSString *)inet6Address
                             mtu:(int)mtu
                           reply:(tunReplyBlock)reply;

- (void)enableProxyWithPort:(int)port
                  socksPort:(int)socksPort
                        pac:(NSString *)pac
            filterInterface:(BOOL)filterInterface
                 ignoreList:(NSArray<NSString *>*)ignoreList
                      error:(stringReplyBlock)reply;

- (void)disableProxyWithFilterInterface:(BOOL)filterInterface
                                  reply:(stringReplyBlock)reply;

- (void)restoreProxyWithCurrentPort:(int)port
                          socksPort:(int)socksPort
                               info:(NSDictionary *)dict
                    filterInterface:(BOOL)filterInterface
                              error:(stringReplyBlock)reply;

- (void)getCurrentProxySetting:(dictReplyBlock)reply;
@end
