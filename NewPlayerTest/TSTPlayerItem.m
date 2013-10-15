//
//  TSTPlayerItem.m
//  NewPlayerTest
//
//  Created by Christopher Kalafarski on 9/18/13.
//  Copyright (c) 2013 Bitnock. All rights reserved.
//

#import "TSTPlayerItem.h"

@interface TSTPlayerItem ()

@property (nonatomic, strong) NSURL *assetURL;

@end

@implementation TSTPlayerItem

- (id)initWithURL:(NSURL *)URL {
  self = [super init];
  if (self) {
    self.assetURL = URL;
  }
  return self;
}

- (AVAsset *)playerAsset {
  NSURL *url = [NSURL URLWithString:@"http://cdn.99percentinvisible.org/wp-content/uploads/89-Bubble-Houses.mp3"];
  AVURLAsset *URLAsset;
  
  if (self.assetURL) {
    URLAsset = [AVURLAsset assetWithURL:self.assetURL];
  } else {
    URLAsset = [AVURLAsset assetWithURL:url];
  }

  return URLAsset;
}

- (BOOL)isEqualToPlayerItem:(id<PRXPlayerItem>)aPlayerItem {
  if ([aPlayerItem.playerAsset isKindOfClass:AVURLAsset.class]
      && [[((AVURLAsset *)self.playerAsset) URL] isEqual:[((AVURLAsset *)aPlayerItem.playerAsset) URL]]) {
    return YES;
  } else {
    return NO;
  }
}

@end
