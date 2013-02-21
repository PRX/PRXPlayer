//
//  PRXAudioPlayer.h
//  PRXNewAudioPlayerTester
//
//  Created by Rebecca Nesson on 2/19/13.
//  Copyright (c) 2013 PRX. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#define PRXDEBUG 1

#if PRXDEBUG
#define PRXLog(...) NSLog(__VA_ARGS__)
#else
#define PRXLog(...)
#endif 

@protocol PRXPlayable <NSObject>

@property (nonatomic, strong, readonly) NSURL *audioURL;
@property (nonatomic, strong, readonly) NSDictionary *mediaItemProperties;
@property (nonatomic) NSTimeInterval playbackCursorPosition;
@property (nonatomic) NSTimeInterval duration;
@property (nonatomic, strong, readonly) NSString *displayTitle;
@property (nonatomic, strong, readonly) NSString *displaySubtitle; 

- (BOOL) isEqualToPlayable:(id<PRXPlayable>)playable; 

@end

@protocol PRXAudioPlayerObserver;

@interface PRXAudioPlayer : UIResponder<AVAudioSessionDelegate> {
    // used for determining when the player crosses a meaningful boundary
    id playerSoftEndBoundaryTimeObserver;
    id playerPeriodicTimeObserver;
    id playerLongPeriodicTimeObserver; 
    NSDate *lastLongPeriodicTimeObserverAction;
    BOOL holdPlayback;
    BOOL waitingForPlayableToBeReadyForPlayback;
    float rateWhenAudioSessionDidBeginInterruption;
    NSDate* dateWhenAudioSessionDidBeginInterruption;
    
    NSUInteger retryCount;
}

+ (id)sharedPlayer;
- (id) initWithAudioSessionManagement:(BOOL)manageSession;

@property (nonatomic, strong) NSObject<PRXPlayable> *currentPlayable; 
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong, readonly) AVPlayerItem *playerItem;
@property (nonatomic, readonly) BOOL isPrebuffering;
@property (nonatomic, readonly) float buffer;
@property (nonatomic, strong, readonly) NSArray *observers;

- (void) playPlayable:(id<PRXPlayable>)playable;
- (void) loadPlayable:(id<PRXPlayable>)playable; 
- (float) rateForPlayable:(id<PRXPlayable>)playable;
- (BOOL) isCurrentPlayable:(NSObject<PRXPlayable> *)playable;

- (void) play;
- (void) pause;
- (void) togglePlayPause;
- (void) stop;

- (id) addObserver:(id<PRXAudioPlayerObserver>)observer persistent:(BOOL)persistent;
- (void) removeObserver:(id<PRXAudioPlayerObserver>)observer; 

@end

@protocol PRXAudioPlayerObserver <NSObject>

- (void) observedPlayerStatusDidChange:(AVPlayer *)player;
- (void) observedPlayerDidObservePeriodicTimeInterval:(AVPlayer *)player;

@end
