//
//  PRXPlayer.m
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

#import "PRXPlayer_private.h"
#import <MediaPlayer/MediaPlayer.h>
#import "Reachability.h"

@implementation PRXPlayer

static const NSString* PlayerStatusContext;
static const NSString* PlayerRateContext;
static const NSString* PlayerErrorContext;
static const NSString* PlayerItemStatusContext;
static const NSString* PlayerItemBufferEmptyContext;

float LongPeriodicTimeObserver = 10.0f;

static PRXPlayer* sharedPlayerInstance;

+ (id)sharedPlayer {
    @synchronized(self) {
        if (sharedPlayerInstance == nil) {
            sharedPlayerInstance = [[self alloc] init];
        }
    }
    
    return sharedPlayerInstance;
}

#pragma mark - Garbage collection

- (void)dealloc {
    [self stopObservingPlayer:self.player];
    [self stopObservingPlayerItem:self.currentPlayerItem];
}

#pragma mark - General player interface
#pragma mark Setup

- (id) init {
    self = [self initWithAudioSessionManagement:YES];
    if (self) {
        
    }
    return self;
}

- (id) initWithAudioSessionManagement:(BOOL)manageSession {
    self = [super init];
    if (self) {
        _observers = [NSMutableArray array];
        
        [UIApplication.sharedApplication beginReceivingRemoteControlEvents];
        
        if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"6.0")) { 
            [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(audioSessionInterruption:)
                                                   name:AVAudioSessionInterruptionNotification
                                                   object:nil];
        }
        
        _reach = [Reachability reachabilityWithHostname:@"www.google.com"];
        
        __weak PRXPlayer *p = self;
        
        self.reach.reachableBlock = ^(Reachability *r) {
            PRXLog(@"REACHABLE");
            [p reachDidBecomeReachable];
        };
        
        self.reach.unreachableBlock = ^(Reachability *r) {
            PRXLog(@"UNREACHABLE");
            [p reachDidBecomeUnreachable];
        };
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reachabilityDidChange:)
                                                     name:kReachabilityChangedNotification
                                                   object:nil];
        
        [self.reach startNotifier];

        if (manageSession) {
            NSError *setCategoryError = nil;
            BOOL success = [[AVAudioSession sharedInstance]
                        setCategory: AVAudioSessionCategoryPlayback
                        error: &setCategoryError];
        
            if (!success) { /* handle the error in setCategoryError */ }
            NSError *activationError = nil;
            success = [[AVAudioSession sharedInstance] setActive:YES error: &activationError];
            if (!success) { /* handle the error in activationError */ }
        
            if (SYSTEM_VERSION_LESS_THAN(@"6.0")) {
                [[AVAudioSession sharedInstance] setDelegate:self];
            }
        }
    }
    return self;
}

- (BOOL)allowsPlaybackViaWWAN {
    return YES;
}

- (NSUInteger)retryLimit {
    return 3;
}

- (BOOL)allowsPlaybackViaWWAN {
    return YES;
}

- (void) setPlayer:(AVPlayer*)player {
    [self stopObservingPlayer:self.player];
    
    _player = player;
    
    [self observePlayer:self.player];
}

- (void) setCurrentPlayable:(NSObject<PRXPlayable> *)playable {
    if (![self isCurrentPlayable:playable]) {
        [self currentPlayableWillChange];
        
        _currentPlayable = playable;
      
      // This should not be necessary if self.player is being managed properly. Should only need to
      // set up observers on the AVPlayer when it's created. EXCEPT for the boundary timer; that needs
      // the change whenever the playable changes.
//        [self observePlayer:self.player];
      
        waitingForPlayableToBeReadyForPlayback = YES;
        if (!holdPlayback) { playerIsBuffering = YES; }
      
        [self reportPlayerStatusChangeToObservers];
      
        self.currentURLAsset = [AVURLAsset assetWithURL:self.currentPlayable.audioURL];
    }
}

- (BOOL) isCurrentPlayable:(NSObject<PRXPlayable> *)playable {
    return [playable isEqualToPlayable:self.currentPlayable];
}

- (void) setCurrentPlayerItem:(AVPlayerItem*)currentPlayerItem {
    [self stopObservingPlayerItem:self.currentPlayerItem];
    
    _currentPlayerItem = currentPlayerItem;
    
    if (!self.player) {
        self.player = [AVPlayer playerWithPlayerItem:self.currentPlayerItem];
        
        float version = UIDevice.currentDevice.systemVersion.floatValue;
        
        if (version >= 6.0f) {
            self.player.allowsExternalPlayback = NO;
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            self.player.allowsAirPlayVideo = NO;
#pragma clang diagnostic pop
        }
    } else {
        [self.player replaceCurrentItemWithPlayerItem:self.currentPlayerItem];
    }
    
    [self observePlayerItem:self.currentPlayerItem];
}

- (void) setCurrentURLAsset:(AVURLAsset*)currentURLAsset {
    _currentURLAsset = currentURLAsset;
  
    [self.player removeTimeObserver:playerSoftEndBoundaryTimeObserver];
    playerSoftEndBoundaryTimeObserver = nil;
    
    [self.currentURLAsset loadValuesAsynchronouslyForKeys:@[@"tracks"] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *error;
            AVKeyValueStatus status = [self.currentURLAsset statusOfValueForKey:@"tracks" error:&error];
            
            if (status == AVKeyValueStatusLoaded) {
                [self didLoadTracksForAsset:self.currentURLAsset];
            } else {
                [self failedToLoadTracksForAsset:self.currentURLAsset];
            }
        });
    }];
}

#pragma mark Exposure

- (AVPlayerItem*) playerItem {
    return self.currentPlayerItem;
}

- (float) buffer {
    CMTimeRange tr;
    [[self.player.currentItem.loadedTimeRanges lastObject] getValue:&tr];
    
    CMTime duration = tr.duration;
    return MAX(0.0f, CMTimeGetSeconds(duration));
}

- (float) rateForPlayable:(NSObject<PRXPlayable> *)playable {
    if ([self isCurrentPlayable:playable]) {
        return self.player.rate;
    }
    return 0.0f;
}

- (BOOL) isWaitingForPlayable:(NSObject<PRXPlayable> *)playable {
  return ([self isCurrentPlayable:playable] && waitingForPlayableToBeReadyForPlayback);
}

#pragma mark Asynchronous loading callbacks

- (void) didLoadTracksForAsset:(AVURLAsset*)asset {
    self.currentPlayerItem = [AVPlayerItem playerItemWithAsset:asset];
}

- (void) failedToLoadTracksForAsset:(AVURLAsset*)asset {
    // loading the tracks using a player url asset is more reliable and has already been tried
    // by the time we get here.  but if it fails we can still try to set the player item directly. 
    self.currentPlayerItem = [AVPlayerItem playerItemWithURL:self.currentPlayable.audioURL];
}

#pragma mark Controls

- (void) loadPlayable:(NSObject<PRXPlayable> *)playable {
    holdPlayback = YES;
    retryCount = 0;
    [self preparePlayable:playable];
}

- (void) playPlayable:(NSObject<PRXPlayable> *)playable {
    holdPlayback = NO;
    retryCount = 0;
    [self preparePlayable:playable];
}

- (void) togglePlayable:(id<PRXPlayable>)playable {
  if ([self rateForPlayable:playable] == 0.0f) {
    [self playPlayable:playable];
  } else {
    [self pause];
  }
}

- (void) preparePlayable:(NSObject<PRXPlayable> *)playable {
    rateWhenAudioSessionDidBeginInterruption = NSNotFound;
    dateWhenAudioSessionDidBeginInterruption = nil;

    restartPlaybackWhenBufferEmpties = NO;
    
    if (![self isCurrentPlayable:playable]) {
        waitingForPlayableToBeReadyForPlayback = NO;
    }
    
    [self loadAndPlayPlayable:playable];
}

- (void) loadAndPlayPlayable:(id<PRXPlayable>)playable {
    if ([self isCurrentPlayable:playable]) {
        if (![self.currentURLAsset.URL isEqual:playable.audioURL]) {
            PRXLog(@"Switching to stream or local file because other is no longer available");
            PRXLog(@"%@ %@", self.currentURLAsset, playable.audioURL);
            waitingForPlayableToBeReadyForPlayback = YES;
            if (!holdPlayback) { playerIsBuffering = YES; }
            self.currentURLAsset = [AVURLAsset assetWithURL:playable.audioURL];
        } else if ([self rateForPlayable:playable] > 0.0f) {
            PRXLog(@"Playable is already playing");
            waitingForPlayableToBeReadyForPlayback = NO;
            return;
        } else if ([self rateForPlayable:playable] == 0.0f && !waitingForPlayableToBeReadyForPlayback) {
            PRXLog(@"Resume (or start) playing current playable");
            
            if ([self.currentPlayable respondsToSelector:@selector(playbackCursorPosition)]) { 
                CMTime startTime;
            
                if (CMTimeGetSeconds(self.player.currentItem.duration) - self.currentPlayable.playbackCursorPosition < 3.0f) {
                    startTime = CMTimeMake(0, 1);
                } else {
                    startTime = CMTimeMakeWithSeconds(self.currentPlayable.playbackCursorPosition, 1);
                }
            
                self.reach.reachableOnWWAN = self.allowsPlaybackViaWWAN;
                if (self.reach.isReachable || [self.currentPlayable.audioURL isFileURL]) {
                    [self.player seekToTime:startTime completionHandler:^(BOOL finished){
                        if (finished && !holdPlayback) {
                            self.player.rate = self.rateForPlayback;
                        } else {
                            PRXLog(@"Not starting playback because of hold or seek interruption");
                        }
                    }];
                } else {
                    PRXLog(@"Aborting playback, network not reachable");
                }
            } else {
                self.reach.reachableOnWWAN = self.allowsPlaybackViaWWAN;
                if (self.reach.isReachable || [self.currentPlayable.audioURL isFileURL]) {
                    if (!holdPlayback) { 
                        self.player.rate = self.rateForPlayback;
                    } else {
                        PRXLog(@"Not starting playback because of a hold or seek interruption");
                    }
                } else {
                    PRXLog(@"Aborting playback, network not reachable");
                }

            }
        } else {
            // should never get here.
            // generally, assuming the waiting flag is correct, we just want to keep waiting...
            
        }
    } else {
        self.reach.reachableOnWWAN = self.allowsPlaybackViaWWAN;
        if (self.reach.isReachable || [playable.audioURL isFileURL]) {
            PRXLog(@"loading episode into player, playback will start async");
            self.currentPlayable = playable;
        } else {
            PRXLog(@"Aborting loading, network not reachable");
        }
    }
}

- (void) reloadAndPlayPlayable:(NSObject<PRXPlayable> *)playable {
    [self stop];
    [self preparePlayable:playable];
}

- (void) play {
    if (self.currentPlayable) {
        holdPlayback = NO; 
        [self loadAndPlayPlayable:self.currentPlayable];
    }
}

- (void) pause {
    self.player.rate = 0.0f;
    playerIsBuffering = NO;
  
    // Hold is being set to prevent cases where the player item unexpectedly reports as being ReadyForPlayback
    // which could cause it to start playing. In iOS 6.0+ this can occur when audio interrupts end.
    // This may be unnecessary when, in playerItemStatusDidChange, playback is only being started if the status
    // actually changed, not any time the player item is reported as ready.
    holdPlayback = YES;
}

- (void) togglePlayPause {
    if (self.player.rate > 0.0f) {
        [self pause];
    } else {
        [self play];
    }
}

- (void) stop {
    PRXLog(@"Stop has been called on the audio player; resetting everything;");
  
    playerIsBuffering = NO;
    waitingForPlayableToBeReadyForPlayback = NO;
    holdPlayback = NO;
  
    _currentPlayable = nil;
  
    _currentPlayerItem = nil;
    _currentURLAsset = nil;
    [self.player removeTimeObserver:playerSoftEndBoundaryTimeObserver];
    playerSoftEndBoundaryTimeObserver = nil; 
    _player.rate = 0.0; 
    _player = nil;
  
    [self reportPlayerStatusChangeToObservers];
}

#pragma mark Target playback rates

- (float) rateForFilePlayback {
    return 1.0f;
}

- (float) rateForPlayback {
    return (self.currentPlayerItem.duration.value > 0 ? self.rateForFilePlayback : 1.0f);
}

#pragma mark Soft end

- (float) softEndBoundaryProgress {
    return 0.95f;
}

#pragma mark Callbacks

- (void) observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
    if (context == &PlayerStatusContext) {
        [self playerStatusDidChange:change];
        return;
    } else if (context == &PlayerRateContext) {
        [self playerRateDidChange:change];
        return;
    } else if (context == &PlayerErrorContext) {
        [self playerErrorDidChange:change];
        return;
    } else if (context == &PlayerItemStatusContext) {
        [self playerItemStatusDidChange:change];
        return;
    } else if (context == &PlayerItemBufferEmptyContext) {
//        [self playerItemStatusDidChange:change];
        [self playerItemBufferEmptied:change];
        return;
    }
    
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    return;
}

- (void) currentPlayableWillChange {
    if (self.currentPlayable) {
        // [self pause];
        self.player.rate = 0.0f;
        [self removeNonPersistentObservers:YES];
        [self.player removeTimeObserver:playerSoftEndBoundaryTimeObserver];
        playerSoftEndBoundaryTimeObserver = nil;
      
      // This should not be necessary if self.player is being managed properly. Should only need to
      // kill observers on the AVPlayer when the player itself is killed (in stop).
      // EXCEPT for the boundary timer; that needs
      // to change whenever the playable changes.
//        [self stopObservingPlayer:self.player];
    }
}

- (void) playerStatusDidChange:(NSDictionary*)change {
    [self reportPlayerStatusChangeToObservers];
}

- (void) playerRateDidChange:(NSDictionary*)change {    
    [self reportPlayerStatusChangeToObservers];
}

- (void) playerErrorDidChange:(NSDictionary*)change {
    [self stop];
    [self reportPlayerStatusChangeToObservers];
}

- (void) playerItemStatusDidChange:(NSDictionary*)change {
    PRXLog(@"Player item status did change to %@", change);
  
    [self reportPlayerStatusChangeToObservers];
    
    NSUInteger keyValueChangeKind = [change[NSKeyValueChangeKindKey] integerValue];
  
    if (keyValueChangeKind == NSKeyValueChangeSetting) {
        if (self.player.currentItem.status == AVPlayerStatusReadyToPlay) {
            waitingForPlayableToBeReadyForPlayback = NO;
            retryCount = 0;
            
            [self setMPNowPlayingInfoCenterNowPlayingInfo];
            PRXLog(@"Player item has become ready to play; pass it back to playEpisode: to get it to start playback.");
          
            // Find a better place for this
            if (self.player.currentItem.duration.value > 0) {
                int64_t boundryTime = ((double)self.player.currentItem.duration.value * self.softEndBoundaryProgress);
                CMTime boundry = CMTimeMake(boundryTime, self.player.currentItem.duration.timescale);
                
                NSValue* _boundry = [NSValue valueWithCMTime:boundry];
                
                __weak id this = self;
                
                playerSoftEndBoundaryTimeObserver = [self.player addBoundaryTimeObserverForTimes:@[ _boundry ] queue:dispatch_queue_create("playerQueue", NULL) usingBlock:^{
                  [this playerSoftEndBoundaryTimeObserverAction];
                }];
            }
        
            [self loadAndPlayPlayable:self.currentPlayable];
        } else if (self.player.currentItem.status == AVPlayerStatusFailed) {
            PRXLog(@"Player status failed %@", self.player.currentItem.error);
            // the AVPlayer has trouble switching from stream to file and vice versa
            // if we get an error condition, start over playing the thing it tried to play.
            // Once a player fails it can't be used for playback anymore!
            waitingForPlayableToBeReadyForPlayback = NO;
            
            if (retryCount < self.retryLimit) {
                retryCount++;
              
                PRXLog(@"Retrying (retry number %i of %i)", retryCount, self.retryLimit);
              
                NSObject<PRXPlayable> *playableToRetry = self.currentPlayable;
                [self stop];
                
                [self preparePlayable:playableToRetry];
            } else {
                PRXLog(@"Playable failed to become ready even after retries.");
                [self stop];
                _currentPlayable = nil;
                [self reportPlayerStatusChangeToObservers];
            }
            
        } else {
            // AVPlayerStatusUnknown
            PRXLog(@"+++++++++++++++++ AVPlayerStatusUnknown +++++++++++++");
            PRXLog(@"This shouldn't happen after an item has become ready.");
        }
    }
}

- (void) playerItemBufferEmptied:(NSDictionary*)change {
    
    self.player.rate = 0;
    PRXLog(@"Buffer emptied, rate %f", self.player.rate);
    // try again?
    // need to make sure the buffer isn't emptying when nothing is actually playing
    // resulting in something starting on its own
    
    // by stopping here we lose any ability for AVPlayer to recover
    if (self.reach.isReachable
        && restartPlaybackWhenBufferEmpties == YES) {
        NSObject<PRXPlayable> *playableToRetry = self.currentPlayable;
        [self stop];
        
        [self playPlayable:playableToRetry];

//        [self reloadAndPlayPlayable:self.currentPlayable];
    }
}

- (void) playerPeriodicTimeObserverAction {
    [self reportPlayerTimeIntervalToObservers];
}

- (void) playerLongPeriodicTimeObserverAction {
    NSTimeInterval since = [lastLongPeriodicTimeObserverAction timeIntervalSinceNow];
    
    if (ABS(since) > LongPeriodicTimeObserver || !lastLongPeriodicTimeObserverAction) {
        lastLongPeriodicTimeObserverAction = [NSDate date];
        [self reportPlayerLongTimeIntervalToObservers]; 
    }
}

- (void) playerSoftEndBoundaryTimeObserverAction {
}

- (void) playerItemDidPlayToEndTime:(NSNotification*)notification {
    restartPlaybackWhenBufferEmpties = NO;
    [self reportPlayerStatusChangeToObservers];
}

- (void) playerItemDidJumpTime:(NSNotification*)notification {
    [self reportPlayerTimeIntervalToObservers];
}

#pragma mark Internal observers

- (void) observePlayer:(AVPlayer*)player {
    [player addObserver:self forKeyPath:@"status" options:0 context:&PlayerStatusContext];
    [player addObserver:self forKeyPath:@"rate" options:0 context:&PlayerRateContext];
    [player addObserver:self forKeyPath:@"error" options:0 context:&PlayerRateContext];
    
    playerPeriodicTimeObserver = [player addPeriodicTimeObserverForInterval:CMTimeMake(1, 1) queue:dispatch_queue_create("playerQueue", NULL) usingBlock:^(CMTime time) {
        [self playerPeriodicTimeObserverAction];
    }];
    
    playerLongPeriodicTimeObserver = [player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(10, 1) queue:dispatch_queue_create("playerQueue", NULL) usingBlock:^(CMTime time) {
        [self playerLongPeriodicTimeObserverAction];
    }];
}

- (void) stopObservingPlayer:(AVPlayer*)player {
    [player removeObserver:self forKeyPath:@"status"];
    [player removeObserver:self forKeyPath:@"rate"];
    [player removeObserver:self forKeyPath:@"error"];
    
    [player removeTimeObserver:playerPeriodicTimeObserver];
    [player removeTimeObserver:playerLongPeriodicTimeObserver];
    [player removeTimeObserver:playerSoftEndBoundaryTimeObserver];
    playerPeriodicTimeObserver = nil;
    playerLongPeriodicTimeObserver = nil;
    playerSoftEndBoundaryTimeObserver = nil;
}

- (void) observePlayerItem:(AVPlayerItem*)playerItem {
    [playerItem addObserver:self forKeyPath:@"status" options:(NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld) context:&PlayerItemStatusContext];
    [playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:0 context:&PlayerItemBufferEmptyContext];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidPlayToEndTime:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:playerItem];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidJumpTime:)
                                                 name:AVPlayerItemTimeJumpedNotification
                                               object:playerItem];
}

- (void) stopObservingPlayerItem:(AVPlayerItem*)playerItem {
    [playerItem removeObserver:self forKeyPath:@"status"];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:playerItem];
}

#pragma mark External observers

- (id) addObserver:(id<PRXPlayerObserver>)observer persistent:(BOOL)persistent {
    if (![self isBeingObservedBy:observer]) {
        NSNumber* _persistent = @(persistent);
        NSDictionary* dict = @{ @"obj":observer, @"persist":_persistent };
        
        NSMutableArray* mArr = [NSMutableArray arrayWithArray:_observers];
        [mArr addObject:dict];
        _observers = [NSArray arrayWithArray:mArr];
    }
    
    return @"YES";
}

- (void) removeObserver:(id<PRXPlayerObserver>)observer {
    NSMutableArray* discardItems = [NSMutableArray array];
    
    for (NSDictionary* dict in _observers) {
        if ([dict[@"obj"] isEqual:observer]) {
            [discardItems addObject:dict];
        }
    }
    
    NSMutableArray* mArr = [NSMutableArray arrayWithArray:_observers];
    [mArr removeObjectsInArray:discardItems];
    _observers = [NSArray arrayWithArray:mArr];
}

- (BOOL) isBeingObservedBy:(id<PRXPlayerObserver>)observer {
    for (NSDictionary* dict in _observers) {
        if ([dict[@"obj"] isEqual:observer]) {
            return YES;
        }
    }
    return NO;
}

- (void) removeNonPersistentObservers:(BOOL)rerun {
    NSMutableArray* discardItems = [NSMutableArray array];
    
    for (NSDictionary* dict in _observers) {
        if ([dict[@"persist"] isEqualToNumber:@NO]) {
            [discardItems addObject:dict];
            id<PRXPlayerObserver> observer = dict[@"obj"];
            
            if (rerun) {
                [observer observedPlayerStatusDidChange:self.player];
                [observer observedPlayerDidObservePeriodicTimeInterval:self.player];
            }
        }
    }
    
    NSMutableArray* mArr = [NSMutableArray arrayWithArray:_observers];
    [mArr removeObjectsInArray:discardItems];
    _observers = [NSArray arrayWithArray:mArr];
}

- (void) reportPlayerStatusChangeToObservers {
    for (NSDictionary* dict in _observers) {
        id<PRXPlayerObserver> observer = dict[@"obj"];
        if ([observer respondsToSelector:@selector(observedPlayerStatusDidChange:)]) {
            [observer observedPlayerStatusDidChange:self.player];
        }
    }
}

- (void) reportPlayerTimeIntervalToObservers {
    for (NSDictionary* dict in _observers) {
        id<PRXPlayerObserver> observer = dict[@"obj"];
        if ([observer respondsToSelector:@selector(observedPlayerDidObservePeriodicTimeInterval:)]) {
            [observer observedPlayerDidObservePeriodicTimeInterval:self.player];
        }
    }
}

- (void) reportPlayerLongTimeIntervalToObservers {
    for (NSDictionary* dict in _observers) {
        id<PRXPlayerObserver> observer = dict[@"obj"];
        if ([observer respondsToSelector:@selector(observedPlayerDidObserveLongPeriodicTimeInterval:)]) {
            [observer observedPlayerDidObserveLongPeriodicTimeInterval:self.player];
        }
    }
}

#pragma mark Keep Alive

- (void) keepAliveInBackground {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self beginBackgroundKeepAlive];
        [NSThread sleepForTimeInterval:240];
        [self endBackgroundKeepAlive];
    });
}

- (void) beginBackgroundKeepAlive {
    backgroundKeepAliveTaskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [self endBackgroundKeepAlive];
    }];
}

- (void) endBackgroundKeepAlive {
    [[UIApplication sharedApplication] endBackgroundTask:backgroundKeepAliveTaskID];
    backgroundKeepAliveTaskID = UIBackgroundTaskInvalid;
}

#pragma mark Reachability Interruption

- (void) reachabilityDidChange:(NSNotification*)notification {
    PRXLog(@"reachabilityDidChange: %@", notification);
    NSLog(@"isReachable %i", [self.reach isReachable]);
    NSLog(@"isReachableViaWWAN %i", [self.reach isReachableViaWWAN]);
    NSLog(@"isReachableViaWiFi %i", [self.reach isReachableViaWiFi]);
}

- (void) reachDidBecomeUnreachable {
    PRXLog(@"Network has become unreachable...");
    rateWhenAudioSessionDidBeginInterruption = self.player.rate;
    dateWhenAudioSessionDidBeginInterruption = NSDate.date;
    
    [self keepAliveInBackground];
}

- (void) reachDidBecomeReachable {
    NSTimeInterval intervalSinceInterrupt = [NSDate.date timeIntervalSinceDate:dateWhenAudioSessionDidBeginInterruption];
    float interruptLimit = self.interruptResumeTimeLimit;
    PRXLog(@"Reachability was (re)gained after %f seconds. User limit is %f seconds.", intervalSinceInterrupt, interruptLimit);
  
    if (self.player.rate > 0.0f) {
        restartPlaybackWhenBufferEmpties = YES;
        PRXLog(@"Was playing when reachDidBecomeReachable. Set flag to restart playback if buffer empties.");
    } else {
        if (rateWhenAudioSessionDidBeginInterruption == NSNotFound
            || rateWhenAudioSessionDidBeginInterruption > 0) {
            restartPlaybackWhenBufferEmpties = YES;
            PRXLog(@"Playback was playing before reach interrupt (or no interrupt). Set buffer empty flag and try to restart if necessary.");
            restartPlaybackWhenBufferEmpties = YES;
            
            if (rateWhenAudioSessionDidBeginInterruption > 0.0f) {
                if (interruptLimit < 0
                    || (intervalSinceInterrupt <= interruptLimit)) {
                    PRXLog(@"Resuming playback after unreachable; limit not surpassed. rate = %f", rateWhenAudioSessionDidBeginInterruption);
                    if (self.buffer > 0) {
                        self.player.rate = rateWhenAudioSessionDidBeginInterruption;
                    } else {
                        NSObject<PRXPlayable> *playableToRetry = self.currentPlayable;
                        [self stop];
                        
                        [self playPlayable:playableToRetry];
                    }
                }
            }
        } else {
            PRXLog(@"Player was paused before reach interrupt; will likely die, so kill it now and start over.");
            
            if (self.currentPlayable) {
                NSObject<PRXPlayable> *playableToRetry = self.currentPlayable;
                [self stop];
                
                [self loadPlayable:playableToRetry];
            }
        }
    }

    
    rateWhenAudioSessionDidBeginInterruption = NSNotFound;
    dateWhenAudioSessionDidBeginInterruption = nil;
}

#pragma mark Audio Session Interruption

- (void) audioSessionInterruption:(NSNotification*)notification {
    PRXLog(@"An audioSessionInterruption notification was received");
    if ([notification.userInfo[AVAudioSessionInterruptionTypeKey] isEqual:@(AVAudioSessionInterruptionTypeBegan)]) {
        [self audioSessionDidBeginInterruption:notification];
    } else if ([notification.userInfo[AVAudioSessionInterruptionTypeKey] isEqual:@(AVAudioSessionInterruptionTypeEnded)]) {
        [self audioSessionDidEndInterruption:notification];
    }
}

- (void) audioSessionDidBeginInterruption:(NSNotification*)notification {
    PRXLog(@"Audio session has been interrupted... (Rate was %f)", self.player.rate);
    rateWhenAudioSessionDidBeginInterruption = self.player.rate;
    dateWhenAudioSessionDidBeginInterruption = NSDate.date;
}

- (void) audioSessionDidEndInterruption:(NSNotification*)notification {
    NSTimeInterval intervalSinceInterrupt = [NSDate.date timeIntervalSinceDate:dateWhenAudioSessionDidBeginInterruption];
    float interruptLimit = self.interruptResumeTimeLimit;
    PRXLog(@"Audio session has returned from interruption after %f seconds. User limit is %f seconds.", intervalSinceInterrupt, interruptLimit);
    PRXLog(@"Returning playback rate to %f", rateWhenAudioSessionDidBeginInterruption);
  
    if (rateWhenAudioSessionDidBeginInterruption > 0.0f) {
        if (interruptLimit < 0
            || (intervalSinceInterrupt <= interruptLimit)) {
            PRXLog(@"[Resuming playback after interrupt; limit not surpassed.");
            self.player.rate = rateWhenAudioSessionDidBeginInterruption;
        }
    }
    
    rateWhenAudioSessionDidBeginInterruption = NSNotFound;
    dateWhenAudioSessionDidBeginInterruption = nil;
}

- (NSTimeInterval) interruptResumeTimeLimit {
    return 300;
}

#pragma mark - Remote control

- (BOOL) canBecomeFirstResponder {
    return YES;
}

- (BOOL) becomeFirstResponder {
	[super becomeFirstResponder];
	return YES;
}

- (NSDictionary*) MPNowPlayingInfoCenterNowPlayingInfo {
    NSMutableDictionary *info;
    
    if (self.currentPlayable && self.currentPlayable.mediaItemProperties) {
        info = self.currentPlayable.mediaItemProperties.mutableCopy;
    } else {
        info = [NSMutableDictionary dictionaryWithCapacity:10];
    }
    
    //    Set defaults if missing
    NSArray* metadata = self.player.currentItem.asset.commonMetadata;
    
    if (!info[MPMediaItemPropertyPlaybackDuration]) {
        float _playbackDuration = self.currentPlayerItem ? CMTimeGetSeconds(self.currentPlayerItem.duration) : 0.0f;
        NSNumber* playbackDuration = @(_playbackDuration);
        info[MPMediaItemPropertyPlaybackDuration] = playbackDuration;
    }
    
    if (!info[MPNowPlayingInfoPropertyElapsedPlaybackTime]) {
        float _elapsedPlaybackTime = self.currentPlayerItem ? CMTimeGetSeconds(self.currentPlayerItem.currentTime) : 0.0f;
        NSNumber* elapsedPlaybackTime = @(_elapsedPlaybackTime);
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedPlaybackTime;
    }
    
    if (!info[MPMediaItemPropertyArtwork]) {
        NSArray* artworkMetadata = [AVMetadataItem metadataItemsFromArray:metadata
                                                                  withKey:AVMetadataCommonKeyArtwork
                                                                 keySpace:AVMetadataKeySpaceCommon];
        if (artworkMetadata.count > 0) {
            AVMetadataItem* artworkMetadataItem = artworkMetadata[0];
            
            UIImage* artworkImage = [UIImage imageWithData:artworkMetadataItem.value[@"data"]];
            MPMediaItemArtwork* artwork = [[MPMediaItemArtwork alloc] initWithImage:artworkImage];
            
            info[MPMediaItemPropertyArtwork] = artwork;
        }
    }
    
    if (!info[MPMediaItemPropertyTitle]) {
        NSArray* _metadata = [AVMetadataItem metadataItemsFromArray:metadata withKey:AVMetadataCommonKeyTitle keySpace:AVMetadataKeySpaceCommon];
        
        if (_metadata.count > 0) {
            AVMetadataItem* _metadataItem = _metadata[0];
            info[MPMediaItemPropertyTitle] = _metadataItem.value;
        }
    }

    if (!info[MPMediaItemPropertyAlbumTitle]) {
        NSArray* _metadata = [AVMetadataItem metadataItemsFromArray:metadata withKey:AVMetadataCommonKeyAlbumName keySpace:AVMetadataKeySpaceCommon];
        
        if (_metadata.count > 0) {
            AVMetadataItem* _metadataItem = _metadata[0];
            info[MPMediaItemPropertyAlbumTitle] = _metadataItem.value;
        }
    }
    
    if (!info[MPMediaItemPropertyArtist]) {
        NSArray* _metadata = [AVMetadataItem metadataItemsFromArray:metadata withKey:AVMetadataCommonKeyArtist keySpace:AVMetadataKeySpaceCommon];
        
        if (_metadata.count > 0) {
            AVMetadataItem* _metadataItem = _metadata[0];
            info[MPMediaItemPropertyArtist] = _metadataItem.value;
        }
    }
    
    return info; 
}

- (void) setMPNowPlayingInfoCenterNowPlayingInfo {
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = self.MPNowPlayingInfoCenterNowPlayingInfo;
}

- (void) remoteControlReceivedWithEvent:(UIEvent*)event {
	switch (event.subtype) {
		case UIEventSubtypeNone:
			break;
		case UIEventSubtypeMotionShake:
			break;
		case UIEventSubtypeRemoteControlPlay:
            [self play];
			break;
		case UIEventSubtypeRemoteControlPause:
            [self pause];
			break;
		case UIEventSubtypeRemoteControlStop:
            [self stop];
			break;
		case UIEventSubtypeRemoteControlTogglePlayPause:
            [self togglePlayPause];
			break;
		case UIEventSubtypeRemoteControlNextTrack:
			break;
		case UIEventSubtypeRemoteControlPreviousTrack:
			break;
		case UIEventSubtypeRemoteControlBeginSeekingBackward:
			break;
		case UIEventSubtypeRemoteControlEndSeekingBackward:
			break;
		case UIEventSubtypeRemoteControlBeginSeekingForward:
			break;
		case UIEventSubtypeRemoteControlEndSeekingForward:
			break;
		default:
			break;
	}
}

#pragma mark - AVAudioSession Delegate Methods

- (void)beginInterruption {
    PRXLog(@"AVAudioSession Delegate beginInterruption");
    [self audioSessionDidBeginInterruption:nil];
}

- (void)endInterruption {
    PRXLog(@"AVAudioSession Delegate endInterruption");
    [[AVAudioSession sharedInstance] setActive:YES];
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [self audioSessionDidEndInterruption:nil];
}

- (void)endInterruptionWithFlags:(NSUInteger)flags {
    PRXLog(@"AVAudioSession Delegate endInterruptionWithFlags");
    [self endInterruption];
}

- (void)inputIsAvailableChanged:(BOOL)isInputAvailable {
    
}

@end
