//
//  PRXReachability.h
//  NewPlayerTest
//
//  Created by Christopher Kalafarski on 9/20/13.
//  Copyright (c) 2013 Bitnock. All rights reserved.
//

@import Foundation;
@import SystemConfiguration;

typedef NS_ENUM(NSUInteger, PRXReachabilityStatus) {
  PRXReachabilityStatusUnknown,
  PRXReachabilityStatusUnreachable,
  PRXReachabilityStatusWWAN,
  PRXReachabilityStatusWiFi
};

@interface PRXReachabilityMonitor : NSObject

+ (instancetype)defaultMonitor;

+ (instancetype)monitorWithHostname:(NSString *)hostname;
+ (instancetype)monitorWithURL:(NSURL *)URL;

- (id)initWithNetworkReachabilityRef:(SCNetworkReachabilityRef)ref;

@end
