//
//  PRXPlayer.h
//  PRXPlayer
//
//  Copyright (c) 2013 PRX.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

@import UIKit;
@import AVFoundation;

#import "Reachability.h"

@protocol PRXPlayerItem, PRXPlayerDelegate;

extern NSString * const PRXPlayerChangeNotification;
extern NSString * const PRXPlayerTimeIntervalNotification;
extern NSString * const PRXPlayerLongTimeIntervalNotification;

extern NSString * const PRXPlayerReachabilityPolicyPreventedPlayback;

typedef NS_ENUM(NSUInteger, PRXPlayerState) {
  PRXPlayerStateUnknown,
  PRXPlayerStateEmpty,
  PRXPlayerStateLoading,
  PRXPlayerStateBuffering,
  PRXPlayerStateWaiting,
  PRXPlayerStateReady
};

@interface PRXPlayer : UIResponder {
  BOOL holdPlayback;
  
  NSUInteger retryCount;
  
  id playerPeriodicTimeObserver;
  id playerSoftEndBoundaryTimeObserver;
  
  NSUInteger backgroundKeepAliveTaskID;
  NSDate *dateAtAudioPlaybackInterruption;
  
  NetworkStatus previousReachabilityStatus;
  NSString *previousReachabilityString;
}

+ (instancetype)sharedPlayer;

@property (nonatomic, strong, readonly) AVPlayer *player;

@property (nonatomic, readonly) PRXPlayerState state;
@property (nonatomic, readonly) NSTimeInterval buffer;

@property (nonatomic, strong) id<PRXPlayerItem> playerItem;

@property (nonatomic, weak) id<PRXPlayerDelegate> delegate;

- (void)loadPlayerItem:(id<PRXPlayerItem>)playerItem;
- (void)playPlayerItem:(id<PRXPlayerItem>)playerItem;
- (void)togglePlayerItem:(id<PRXPlayerItem>)playerItem orCancel:(BOOL)cancel;
- (void)togglePlayerItem:(id<PRXPlayerItem>)playerItem;

- (void)play;
- (void)pause;
- (void)toggle;
- (void)toggleOrCancel;
- (void)stop;

// this will go away
- (NSDate *)dateAtAudioPlaybackInterruption;

@end

@protocol PRXPlayerItem <NSObject>

@property (nonatomic, strong, readonly) AVAsset *playerAsset;

- (BOOL)isEqualToPlayerItem:(id<PRXPlayerItem>)aPlayerItem;

@optional

@property (nonatomic, strong, readonly) NSDictionary *mediaItemProperties;

// TODO better names
@property (nonatomic, readonly) CMTime playerTime;
@property (nonatomic, readonly) CMTime playerDuration;

- (void)setPlayerTime:(CMTime)playerTime;
- (void)setPlayerDuration:(CMTime)playerDuration;

@end

@protocol PRXPlayerDelegate <NSObject>

//- (void)player:(AVPlayer *)player changedToTime:(CMTime);
//- (void)playerDidTraverseSoftEndBoundaryTime:(PRXPlayer *)player;

@optional

- (AVAsset *)player:(PRXPlayer *)player assetForPlayerItem:(id<PRXPlayerItem>)playerItem;

- (void)player:(PRXPlayer *)player failedToLoadTracksForAsset:(AVAsset *)asset holdPlayback:(BOOL)holdPlayback;
- (void)playerFailedToBecomeReadyToPlay:(PRXPlayer *)player holdPlayback:(BOOL)holdPlayback;

- (void)player:(PRXPlayer *)player softBoundaryTimeReachedForPlayerItem:(AVPlayerItem *)playerItem;
- (void)player:(PRXPlayer *)player endTimeReachedForPlayerItem:(AVPlayerItem *)playerItem;
- (void)player:(PRXPlayer *)player playerItemDidChange:(NSDictionary *)change;
- (void)player:(PRXPlayer *)player currentItemStatusDidChange:(NSDictionary *)change;
- (void)player:(PRXPlayer *)player rateDidChange:(NSDictionary *)change;

- (float)filePlaybackRateForPlayer:(PRXPlayer *)player;
- (BOOL)playerAllowsPlaybackViaWWAN:(PRXPlayer *)player;
- (float)softEndBoundaryProgressForPlayer:(PRXPlayer *)player;
- (NSUInteger)retryLimitForPlayer:(PRXPlayer *)player;

@end
