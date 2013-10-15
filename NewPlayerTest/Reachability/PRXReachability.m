//
//  PRXReachability.m
//  NewPlayerTest
//
//  Created by Christopher Kalafarski on 9/20/13.
//  Copyright (c) 2013 Bitnock. All rights reserved.
//

#import "PRXReachability.h"

@interface PRXReachabilityMonitor ()

@property (nonatomic, assign) SCNetworkReachabilityRef networkReachabilityRef;

@end

@implementation PRXReachabilityMonitor

+ (instancetype)defaultMonitor {
  static dispatch_once_t _defaultPredicate;
  static id _defaultInstance = nil;
  
  dispatch_once(&_defaultPredicate, ^{
    _defaultInstance = [self monitorWithHostname:@"www.google.com"];
  });
  
  return _defaultInstance;
}

+ (instancetype)monitorWithHostname:(NSString *)hostname {
  SCNetworkReachabilityRef ref;
  ref = SCNetworkReachabilityCreateWithName(NULL, hostname.UTF8String);

  if (ref) {
    return [[self alloc] initWithNetworkReachabilityRef:ref];
  }
  
  return nil;
}

+ (instancetype)monitorWithURL:(NSURL *)URL {
  return [self monitorWithHostname:URL.host];
}

- (id)initWithNetworkReachabilityRef:(SCNetworkReachabilityRef)ref {
  self = [super init];
  if (self) {
    self.networkReachabilityRef = ref;
  }
  return self;
}

@end
