//
//  PRXAudioPlayer_private.h
//  PRXNewAudioPlayerTester
//
//  Created by Rebecca Nesson on 2/19/13.
//  Copyright (c) 2013 PRX. All rights reserved.
//

#import "PRXAudioPlayer.h"
#import "Reachability.h"

@interface PRXAudioPlayer ()

extern float LongPeriodicTimeObserver;

@property (nonatomic, strong) AVURLAsset *currentURLAsset;
@property (nonatomic, strong) AVPlayerItem *currentPlayerItem;

- (void) didLoadTracksForAsset:(AVURLAsset *)asset;
- (void) failedToLoadTracksForAsset:(AVURLAsset *)asset;

@property (nonatomic, readonly) float rateForFilePlayback;
@property (nonatomic, readonly) float rateForPlayback;

@property (nonatomic, readonly) float softEndBoundaryProgress; // between 0.0 and 1.0

@property (nonatomic, strong, readonly) Reachability *reach;
@property (nonatomic, readonly) BOOL allowsPlaybackViaWWAN;
@property (nonatomic, readonly) NSTimeInterval interruptResumeTimeLimit; 

- (void)loadAndPlayPlayable:(id<PRXPlayable>)playable;

- (void) currentPlayableWillChange;
- (void)playerStatusDidChange:(NSDictionary*)change;
- (void)playerRateDidChange:(NSDictionary*)change;
- (void)playerErrorDidChange:(NSDictionary*)change;
- (void)playerItemStatusDidChange:(NSDictionary*)change;
- (void)playerItemBufferEmptied:(NSDictionary*)change;
- (void)playerPeriodicTimeObserverAction;
- (void)playerLongPeriodicTimeObserverAction;
- (void)playerSoftEndBoundaryTimeObserverAction;
- (void)playerItemDidPlayToEndTime:(NSNotification*)notification;
- (void)playerItemDidJumpTime:(NSNotification*)notification;

- (void)audioSessionDidBeginInterruption:(NSNotification*)notification;
- (void)audioSessionDidEndInterruption:(NSNotification*)notification;
- (void)audioSessionInterruption:(NSNotification*)notification;

- (void) didBeginBufferInterruption;
- (void) didEndBufferInterruption; 

- (void)observePlayer:(AVPlayer*)player;
- (void)stopObservingPlayer:(AVPlayer*)player;

- (void)observePlayerItem:(AVPlayerItem*)playerItem;
- (void)stopObservingPlayerItem:(AVPlayerItem*)playerItem;

- (BOOL)isBeingObservedBy:(id<PRXAudioPlayerObserver>)observer;
- (void)removeNonPersistentObservers:(BOOL)rerun;

- (void)reportPlayerStatusChangeToObservers;
- (void)reportPlayerTimeIntervalToObservers;

- (NSDictionary*)MPNowPlayingInfoCenterNowPlayingInfo;
- (void)setMPNowPlayingInfoCenterNowPlayingInfo;
- (NSString *)defaultNowPlayingArtist;

@end
