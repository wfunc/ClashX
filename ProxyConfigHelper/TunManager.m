//
//  TunManager.m
//  com.west2online.ClashX.ProxyConfigHelper
//

#import "TunManager.h"

#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/sys_domain.h>
#include <sys/kern_control.h>
#include <net/if.h>
#include <net/if_utun.h>
#include <arpa/inet.h>

// Same all-IPv4 / all-IPv6 sub-range split that sing-tun installs for
// auto-route on darwin. Using sub-ranges instead of replacing the default
// route keeps the real 0.0.0.0/0 via the physical interface intact, which
// is what the core's auto-detect-interface relies on to bind outbound
// connections and avoid a routing loop.
static NSArray<NSString *> *kInet4RouteRanges(void) {
    return @[ @"1.0.0.0/8", @"2.0.0.0/7", @"4.0.0.0/6", @"8.0.0.0/5",
              @"16.0.0.0/4", @"32.0.0.0/3", @"64.0.0.0/2", @"128.0.0.0/1" ];
}

static NSArray<NSString *> *kInet6RouteRanges(void) {
    return @[ @"100::/8", @"200::/7", @"400::/6", @"800::/5",
              @"1000::/4", @"2000::/3", @"4000::/2", @"8000::/1" ];
}

@implementation TunManager

+ (void)startTunWithInet4Address:(NSString *)inet4Address
                    inet6Address:(NSString *)inet6Address
                             mtu:(int)mtu
                           reply:(void (^)(NSFileHandle *_Nullable,
                                           NSString *_Nullable,
                                           NSString *_Nullable))reply {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.west2online.ClashX.ProxyConfigHelper.tun", DISPATCH_QUEUE_SERIAL);
    });
    dispatch_async(queue, ^{
        [self createAndConfigureTunWithInet4Address:inet4Address inet6Address:inet6Address mtu:mtu reply:reply];
    });
}

+ (void)createAndConfigureTunWithInet4Address:(NSString *)inet4Address
                                 inet6Address:(NSString *)inet6Address
                                          mtu:(int)mtu
                                        reply:(void (^)(NSFileHandle *_Nullable,
                                                        NSString *_Nullable,
                                                        NSString *_Nullable))reply {
    NSString *addr4 = nil;
    NSString *mask4 = nil;
    if (![self parseInet4CIDR:inet4Address address:&addr4 netmask:&mask4]) {
        reply(nil, nil, [NSString stringWithFormat:@"invalid inet4 address: %@", inet4Address]);
        return;
    }

    NSString *utunError = nil;
    NSString *ifName = nil;
    int fd = [self createUtun:&ifName error:&utunError];
    if (fd < 0) {
        reply(nil, nil, utunError ?: @"failed to create utun device");
        return;
    }

    int effectiveMtu = mtu > 0 ? mtu : 1500;
    NSString *error = [self runTool:@"/sbin/ifconfig"
                               args:@[ ifName, addr4, addr4,
                                       @"netmask", mask4,
                                       @"mtu", [NSString stringWithFormat:@"%d", effectiveMtu],
                                       @"up" ]];
    if (error) {
        close(fd);
        reply(nil, nil, [NSString stringWithFormat:@"ifconfig %@ failed: %@", ifName, error]);
        return;
    }

    NSString *addr6 = nil;
    NSString *prefix6 = nil;
    BOOL hasV6 = inet6Address.length > 0 && [self parseInet6CIDR:inet6Address address:&addr6 prefixLength:&prefix6];
    if (hasV6) {
        error = [self runTool:@"/sbin/ifconfig" args:@[ ifName, @"inet6", addr6, @"prefixlen", prefix6 ]];
        if (error) {
            // IPv6 is best-effort: a v4-only tun is still functional.
            NSLog(@"TunManager: ifconfig inet6 failed: %@", error);
            hasV6 = NO;
        }
    }

    for (NSString *range in kInet4RouteRanges()) {
        error = [self installRoute:range gateway:addr4 ifName:ifName inet6:NO];
        if (error) {
            // Closing the fd makes the kernel purge the routes added so far.
            close(fd);
            reply(nil, nil, error);
            return;
        }
    }

    if (hasV6) {
        for (NSString *range in kInet6RouteRanges()) {
            NSString *v6Error = [self installRoute:range gateway:addr6 ifName:ifName inet6:YES];
            if (v6Error) {
                NSLog(@"TunManager: %@", v6Error);
            }
        }
    }

    [self runTool:@"/usr/bin/dscacheutil" args:@[ @"-flushcache" ]];

    // closeOnDealloc drops the helper's copy after the fd is serialized into
    // the XPC reply, leaving the app as the sole owner. The interface (and
    // its routes) then dies automatically with the app's fd — even on crash.
    NSFileHandle *handle = [[NSFileHandle alloc] initWithFileDescriptor:fd closeOnDealloc:YES];
    reply(handle, ifName, nil);
}

// MARK: - routes

// Other full-tunnel VPNs (anything sing-tun based, OpenVPN def1, ...) install
// these same destinations, and `route delete` matches by destination only —
// deleting blindly would permanently break a concurrently running VPN. So
// add first, and on conflict replace the route only when it already points
// at our own utun; otherwise refuse with a clear error.
+ (nullable NSString *)installRoute:(NSString *)range gateway:(NSString *)gateway ifName:(NSString *)ifName inet6:(BOOL)inet6 {
    NSArray *family = inet6 ? @[ @"-inet6" ] : @[];
    NSArray *addArgs = [@[ @"-n", @"add" ] arrayByAddingObjectsFromArray:
                        [family arrayByAddingObjectsFromArray:@[ @"-net", range, gateway ]]];
    NSString *error = [self runTool:@"/sbin/route" args:addArgs];
    if (error == nil) {
        return nil;
    }

    NSString *info = nil;
    [self runTool:@"/sbin/route"
             args:[@[ @"-n", @"get" ] arrayByAddingObjectsFromArray:
                   [family arrayByAddingObjectsFromArray:@[ @"-net", range ]]]
           output:&info];
    BOOL ownedByUs = info != nil &&
        ([info containsString:[NSString stringWithFormat:@"interface: %@\n", ifName]] ||
         [info containsString:[NSString stringWithFormat:@"gateway: %@\n", gateway]]);
    if (!ownedByUs) {
        return [NSString stringWithFormat:@"route %@ is in use by another interface — another VPN appears to be active (%@)", range, error];
    }

    [self runTool:@"/sbin/route"
             args:[@[ @"-n", @"delete" ] arrayByAddingObjectsFromArray:
                   [family arrayByAddingObjectsFromArray:@[ @"-net", range ]]]];
    error = [self runTool:@"/sbin/route" args:addArgs];
    return error ? [NSString stringWithFormat:@"route add %@ failed: %@", range, error] : nil;
}

// MARK: - utun

+ (int)createUtun:(NSString **)ifNameOut error:(NSString **)errorOut {
    int fd = socket(PF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL);
    if (fd < 0) {
        *errorOut = [NSString stringWithFormat:@"socket(PF_SYSTEM): %s", strerror(errno)];
        return -1;
    }

    struct ctl_info info;
    memset(&info, 0, sizeof(info));
    strlcpy(info.ctl_name, UTUN_CONTROL_NAME, sizeof(info.ctl_name));
    if (ioctl(fd, CTLIOCGINFO, &info) < 0) {
        *errorOut = [NSString stringWithFormat:@"ioctl(CTLIOCGINFO): %s", strerror(errno)];
        close(fd);
        return -1;
    }

    struct sockaddr_ctl addr;
    memset(&addr, 0, sizeof(addr));
    addr.sc_len = sizeof(addr);
    addr.sc_family = AF_SYSTEM;
    addr.ss_sysaddr = AF_SYS_CONTROL;
    addr.sc_id = info.ctl_id;
    addr.sc_unit = 0; // let the kernel pick the first free utun unit

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        *errorOut = [NSString stringWithFormat:@"connect(utun): %s", strerror(errno)];
        close(fd);
        return -1;
    }

    char ifName[IFNAMSIZ] = {0};
    socklen_t ifNameLen = sizeof(ifName);
    if (getsockopt(fd, SYSPROTO_CONTROL, UTUN_OPT_IFNAME, ifName, &ifNameLen) < 0) {
        *errorOut = [NSString stringWithFormat:@"getsockopt(UTUN_OPT_IFNAME): %s", strerror(errno)];
        close(fd);
        return -1;
    }

    *ifNameOut = [NSString stringWithUTF8String:ifName];
    return fd;
}

// MARK: - address parsing

static BOOL parsePrefixLength(NSString *text, int maxValue, int *valueOut) {
    if (text.length == 0 || text.length > 3) {
        return NO;
    }
    int value = 0;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (c < '0' || c > '9') {
            return NO;
        }
        value = value * 10 + (c - '0');
    }
    if (value > maxValue) {
        return NO;
    }
    *valueOut = value;
    return YES;
}

+ (BOOL)parseInet4CIDR:(NSString *)cidr address:(NSString **)addressOut netmask:(NSString **)netmaskOut {
    NSArray<NSString *> *parts = [cidr componentsSeparatedByString:@"/"];
    NSString *address = parts.firstObject;
    int prefixLength = 32;
    if (parts.count > 2 || address.length == 0 ||
        (parts.count == 2 && !parsePrefixLength(parts[1], 32, &prefixLength))) {
        return NO;
    }
    struct in_addr parsed;
    if (inet_pton(AF_INET, address.UTF8String, &parsed) != 1) {
        return NO;
    }
    uint32_t mask = prefixLength == 0 ? 0 : (uint32_t)(0xFFFFFFFFu << (32 - prefixLength));
    *addressOut = address;
    *netmaskOut = [NSString stringWithFormat:@"%u.%u.%u.%u",
                   (mask >> 24) & 0xFF, (mask >> 16) & 0xFF, (mask >> 8) & 0xFF, mask & 0xFF];
    return YES;
}

+ (BOOL)parseInet6CIDR:(NSString *)cidr address:(NSString **)addressOut prefixLength:(NSString **)prefixOut {
    NSArray<NSString *> *parts = [cidr componentsSeparatedByString:@"/"];
    NSString *address = parts.firstObject;
    int prefixLength = 128;
    if (parts.count > 2 || address.length == 0 ||
        (parts.count == 2 && !parsePrefixLength(parts[1], 128, &prefixLength))) {
        return NO;
    }
    struct in6_addr parsed;
    if (inet_pton(AF_INET6, address.UTF8String, &parsed) != 1) {
        return NO;
    }
    *addressOut = address;
    *prefixOut = [NSString stringWithFormat:@"%d", prefixLength];
    return YES;
}

// MARK: - command runner

// Returns nil on success, otherwise a message containing exit status and output.
+ (nullable NSString *)runTool:(NSString *)path args:(NSArray<NSString *> *)args {
    return [self runTool:path args:args output:NULL];
}

+ (nullable NSString *)runTool:(NSString *)path args:(NSArray<NSString *> *)args output:(NSString **)outputOut {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = path;
    task.arguments = args;

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    @try {
        [task launch];
    } @catch (NSException *exception) {
        return [NSString stringWithFormat:@"failed to launch %@: %@", path, exception.reason];
    }
    // Drain before waiting: a child blocked on a full pipe would otherwise
    // never exit. EOF arrives when the child exits.
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];

    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    if (outputOut) {
        *outputOut = output;
    }
    if (task.terminationStatus == 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"exit %d: %@", task.terminationStatus,
            [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
}

@end
