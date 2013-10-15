//
//  TSTSwappingPlayerItem.m
//  NewPlayerTest
//
//  Created by Christopher Kalafarski on 9/19/13.
//  Copyright (c) 2013 Bitnock. All rights reserved.
//

#import "TSTSwappingPlayerItem.h"

@interface TSTSwappingPlayerItem () {
  BOOL useLocalURL;
  CMTime __playheadTime;
}

@end

@implementation TSTSwappingPlayerItem

- (id)init {
  self = [super init];
  if (self) {
    __playheadTime = kCMTimeZero;
    self.remoteURL = [NSURL URLWithString:@"http://cdn.99percentinvisible.org/wp-content/uploads/89-Bubble-Houses.mp3"];
    self.localURL = [[NSBundle mainBundle] URLForResource:@"89-Bubble-Houses" withExtension:@"mp3"];
  }
  return self;
}

- (AVAsset *)playerAsset {
  NSURL *currentURL = (useLocalURL ? self.localURL : self.remoteURL);
  return [AVURLAsset assetWithURL:currentURL];
}

- (BOOL)isEqualToPlayerItem:(id<PRXPlayerItem>)aPlayerItem {
  if ([aPlayerItem isKindOfClass:TSTSwappingPlayerItem.class]
      && [self.remoteURL isEqual:[((TSTSwappingPlayerItem *)aPlayerItem) remoteURL]]) {
    return YES;
  } else if ([[aPlayerItem playerAsset] isKindOfClass:AVURLAsset.class]
      && [[((AVURLAsset *)aPlayerItem.playerAsset) URL] isEqual:self.remoteURL]) {
    return YES;
  } else {
    return NO;
  }
}

- (void)swap {
  useLocalURL = !useLocalURL;
}

- (CMTime)playerTime {
  return __playheadTime;
}

- (void)setPlayerTime:(CMTime)playerTime {
  __playheadTime = playerTime;
}

@end
