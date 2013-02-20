//
//  PRXAudioPlayer.m
//  PRXNewAudioPlayerTester
//
//  Created by Rebecca Nesson on 2/19/13.
//  Copyright (c) 2013 PRX. All rights reserved.
//

#import "PRXAudioPlayer.h"
#import "PRXAudioPlayer_private.h"
#import <MediaPlayer/MediaPlayer.h>

@implementation PRXAudioPlayer

static const NSString* PlayerStatusContext;
static const NSString* PlayerRateContext;
static const NSString* PlayerErrorContext;
static const NSString* PlayerItemStatusContext;
static const NSString* PlayerItemBufferEmptyContext;

float LongPeriodicTimeObserver = 10.0f;

static PRXAudioPlayer* sharedPlayerInstance;

+ (PRXAudioPlayer*)sharedPlayer {
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

- (id)init {
    self = [super init];
    if (self) {
        _observers = [NSMutableArray array];
        
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(audioSessionInterruption:)
                                                   name:AVAudioSessionInterruptionNotification object:nil];
        _reach = [Reachability reachabilityWithHostname:@"www.google.com"];
        __block PRXAudioPlayer *p = self; 
        self.reach.reachableBlock = ^(Reachability *r) {
            [p didEndBufferInterruption];
        };
        NSError *setCategoryError = nil;
        BOOL success = [[AVAudioSession sharedInstance]
                        setCategory: AVAudioSessionCategoryAmbient
                        error: &setCategoryError];
        
        if (!success) { /* handle the error in setCategoryError */ }
        NSError *activationError = nil;
        success = [[AVAudioSession sharedInstance] setActive: YES error: &activationError];
        if (!success) { /* handle the error in activationError */ }
        
        [[AVAudioSession sharedInstance] setDelegate:self]; 


    }
    return self;
}

- (void)setPlayer:(AVPlayer*)player {
    [self stopObservingPlayer:self.player];
    
    _player = player;
    
    [self observePlayer:self.player];
}

- (void)setCurrentPlayable:(NSObject<PRXPlayable> *)playable {
    if (![self isCurrentPlayable:playable]) {
        [self currentPlayableWillChange];
        
        _currentPlayable = playable;
        [self observePlayer:self.player];
        
        waitingForPlayableToBeReadyForPlayback = YES; 
        
        self.currentURLAsset = [AVURLAsset assetWithURL:self.currentPlayable.audioURL];
    }
}

- (BOOL)isCurrentPlayable:(NSObject<PRXPlayable> *)playable {
    return [playable isEqualToPlayable:self.currentPlayable];
}

- (void)setCurrentPlayerItem:(AVPlayerItem*)currentPlayerItem {
    [self stopObservingPlayerItem:self.currentPlayerItem];
    
    _currentPlayerItem = currentPlayerItem;
    
    if (!self.player) {
        self.player = [AVPlayer playerWithPlayerItem:self.currentPlayerItem];
        self.player.allowsAirPlayVideo = NO;
        self.player.allowsExternalPlayback = NO; 
    } else {
        [self.player replaceCurrentItemWithPlayerItem:self.currentPlayerItem];
    }
    
    [self observePlayerItem:self.currentPlayerItem];
}

- (void)setCurrentURLAsset:(AVURLAsset*)currentURLAsset {
    _currentURLAsset = currentURLAsset;
    [self.player removeTimeObserver:playerSoftEndBoundaryTimeObserver];
    
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

- (AVPlayerItem*)playerItem {
    return self.currentPlayerItem;
}

- (float)buffer {
    CMTimeRange tr;
    [[self.player.currentItem.loadedTimeRanges lastObject] getValue:&tr];
    
    CMTime duration = tr.duration;
    return MAX(0.0f, CMTimeGetSeconds(duration));
}

#pragma mark Asynchronous loading callbacks

- (void)didLoadTracksForAsset:(AVURLAsset*)asset {
    self.currentPlayerItem = [AVPlayerItem playerItemWithAsset:asset];
}

- (void)failedToLoadTracksForAsset:(AVURLAsset*)asset {
    // loading the tracks using a player url asset is more reliable and has already been tried
    // by the time we get here.  but if it fails we can still try to set the player item directly. 
    self.currentPlayerItem = [AVPlayerItem playerItemWithURL:self.currentPlayable.audioURL];
}

#pragma mark Controls

- (void)loadPlayable:(NSObject<PRXPlayable> *)playable {
    holdPlayback = YES;
    if (![self isCurrentPlayable:playable]) {
        waitingForPlayableToBeReadyForPlayback = NO;
    }
    [self loadAndPlayPlayable:playable];
}

- (void)playPlayable:(NSObject<PRXPlayable> *)playable {
    holdPlayback = NO;
    if (![self isCurrentPlayable:playable]) { 
        waitingForPlayableToBeReadyForPlayback = NO;
    }
    [self loadAndPlayPlayable:playable];
}

- (float) rateForPlayable:(NSObject<PRXPlayable> *)playable {
    if ([self isCurrentPlayable:playable]) {
        return self.player.rate;
    }
    return 0.0f; 
}

- (void)loadAndPlayPlayable:(id<PRXPlayable>)playable {
    if ([self isCurrentPlayable:playable] && ![self.currentURLAsset.URL isEqual:playable.audioURL]) {
        PRXLog(@"Switching to stream or local file because other is no longer available");
        PRXLog(@"%@ %@", self.currentURLAsset, playable.audioURL);  
        self.currentURLAsset = [AVURLAsset assetWithURL:playable.audioURL];
    } else if ([self rateForPlayable:playable] > 0.0f) {
        PRXLog(@"Playable is already playing");
        return;
    } else if ([self isCurrentPlayable:playable] && [self rateForPlayable:playable] <= 0.0f && !waitingForPlayableToBeReadyForPlayback) {
        PRXLog(@"Resume (or start) playing current playable %@", self.currentPlayable.description);
        CMTime startTime;
        
        if (self.currentPlayable.duration - self.currentPlayable.playbackCursorPosition < 3.0f) {
            startTime = CMTimeMake(0, 1);
        } else {
            startTime = CMTimeMakeWithSeconds(self.currentPlayable.playbackCursorPosition, 10);
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
    } else if (!waitingForPlayableToBeReadyForPlayback) {
        self.reach.reachableOnWWAN = self.allowsPlaybackViaWWAN;
        if (self.reach.isReachable || [self.currentPlayable.audioURL isFileURL]) {
            PRXLog(@"loading episode into player, playback will start async %@", [playable description]);
            self.currentPlayable = playable;
            
        } else {
            PRXLog(@"Aborting loading, network not reachable");
        }
    } else {
        PRXLog(@"Waiting for ready to play %@", [playable description]);
    }
}

- (void) reloadAndPlayPlayable:(NSObject<PRXPlayable> *)playable
{
    [self stop];
    [self loadAndPlayPlayable:playable]; 
}

- (void)play {
    if (self.currentPlayable) {
        [self loadAndPlayPlayable:self.currentPlayable];
    }
}

- (void)pause {
    self.player.rate = 0.0f;
}

- (void)togglePlayPause {
    if (self.player.rate > 0.0f) {
        [self pause];
    } else {
        [self play];
    }
}

- (void)stop {
    self.currentPlayerItem = nil;
    self.currentURLAsset = nil;
    self.player = nil;
}

#pragma mark Target playback rates

- (float)rateForFilePlayback {
    return 1.0f;
}

- (float)rateForPlayback {
    return (self.currentPlayerItem.duration.value > 0 ? self.rateForFilePlayback : 1.0f);
}

#pragma mark Soft end

- (float)softEndBoundaryProgress {
    return 0.95f;
}

#pragma mark Callbacks

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
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
        [self playerItemStatusDidChange:change];
        [self playerItemBufferEmptied:change]; 
        return;
    }
    
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    return;
}


- (void)currentPlayableWillChange {
    if (self.currentPlayable) {
        [self pause];
        [self removeNonPersistentObservers:YES];
        [self stopObservingPlayer:self.player];
    }
}

- (void)playerStatusDidChange:(NSDictionary*)change {
    [self reportPlayerStatusChangeToObservers];
}

- (void)playerRateDidChange:(NSDictionary*)change {    
    [self reportPlayerStatusChangeToObservers];
}

- (void)playerErrorDidChange:(NSDictionary*)change {
    [self reportPlayerStatusChangeToObservers];
}

- (void)playerItemStatusDidChange:(NSDictionary*)change {
    PRXLog(@"Player item status did change to %@", change); 
    [self reportPlayerStatusChangeToObservers];
    if ([change[@"kind"] integerValue] == 1) {
        if (self.player.currentItem.status == AVPlayerStatusReadyToPlay) {
            waitingForPlayableToBeReadyForPlayback = NO;
            
            [self setMPNowPlayingInfoCenterNowPlayingInfo];
            PRXLog(@"Player item has become ready to play; pass it back to playEpisode: to get it to start playback.");
            [self loadAndPlayPlayable:self.currentPlayable];
        } else if (self.player.currentItem.status == AVPlayerStatusFailed) {
            PRXLog(@"Player status failed %@", self.player.currentItem.error);
            // the AVPlayer has trouble switching from stream to file and vice versa
            // if we get an error condition, start over playing the thing it tried to play
            waitingForPlayableToBeReadyForPlayback = NO;
            NSObject<PRXPlayable> *tmp = self.currentPlayable;
            [self stop];
            [self playPlayable:tmp];
        }
    }
}

- (void)playerItemBufferEmptied:(NSDictionary*)change {
    
    if ([self.reach isReachable]) { // reload current playable and try again
        [self reloadAndPlayPlayable:self.currentPlayable];
    } else {  // set up state for when network reconnects
        [self didBeginBufferInterruption];
    }
}

- (void)playerPeriodicTimeObserverAction {
    [self reportPlayerTimeIntervalToObservers];
}

- (void)playerLongPeriodicTimeObserverAction {
    NSTimeInterval since = [lastLongPeriodicTimeObserverAction timeIntervalSinceNow];
    
    if (ABS(since) > LongPeriodicTimeObserver || !lastLongPeriodicTimeObserverAction) {
        lastLongPeriodicTimeObserverAction = [NSDate date];
    }
}

- (void)playerSoftEndBoundaryTimeObserverAction {
}

- (void)playerItemDidPlayToEndTime:(NSNotification*)notification {
    [self reportPlayerStatusChangeToObservers];
}

- (void)playerItemDidJumpTime:(NSNotification*)notification {
    [self reportPlayerTimeIntervalToObservers];
}

#pragma mark Internal observers

- (void)observePlayer:(AVPlayer*)player {
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

- (void)stopObservingPlayer:(AVPlayer*)player {
    [player removeObserver:self forKeyPath:@"status"];
    [player removeObserver:self forKeyPath:@"rate"];
    [player removeObserver:self forKeyPath:@"error"];
    
    [player removeTimeObserver:playerPeriodicTimeObserver];
    [player removeTimeObserver:playerLongPeriodicTimeObserver];
}

- (void)observePlayerItem:(AVPlayerItem*)playerItem {
    [playerItem addObserver:self forKeyPath:@"status" options:0 context:&PlayerItemStatusContext];
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

- (void)stopObservingPlayerItem:(AVPlayerItem*)playerItem {
    [playerItem removeObserver:self forKeyPath:@"status"];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:playerItem];
}

#pragma mark External observers

- (id)addObserver:(id<PRXAudioPlayerObserver>)observer persistent:(BOOL)persistent {
    if (![self isBeingObservedBy:observer]) {
        NSNumber* _persistent = @(persistent);
        NSDictionary* dict = @{ @"obj":observer, @"persist":_persistent };
        
        NSMutableArray* mArr = [NSMutableArray arrayWithArray:_observers];
        [mArr addObject:dict];
        _observers = [NSArray arrayWithArray:mArr];
    }
    
    return @"YES";
}

- (void)removeObserver:(id<PRXAudioPlayerObserver>)observer {
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

- (BOOL)isBeingObservedBy:(id<PRXAudioPlayerObserver>)observer {
    for (NSDictionary* dict in _observers) {
        if ([dict[@"obj"] isEqual:observer]) {
            return YES;
        }
    }
    return NO;
}

- (void)removeNonPersistentObservers:(BOOL)rerun {
    NSMutableArray* discardItems = [NSMutableArray array];
    
    for (NSDictionary* dict in _observers) {
        if ([dict[@"persist"] isEqualToNumber:@NO]) {
            [discardItems addObject:dict];
            id<PRXAudioPlayerObserver> observer = dict[@"obj"];
            
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

- (void)reportPlayerStatusChangeToObservers {
    for (NSDictionary* dict in _observers) {
        id<PRXAudioPlayerObserver> observer = dict[@"obj"];
        [observer observedPlayerStatusDidChange:self.player];
    }
}

- (void)reportPlayerTimeIntervalToObservers {
    for (NSDictionary* dict in _observers) {
        id<PRXAudioPlayerObserver> observer = dict[@"obj"];
        [observer observedPlayerDidObservePeriodicTimeInterval:self.player];
    }
}

#pragma mark Reachability Interruption

- (void) didBeginBufferInterruption {
    PRXLog(@"Audio session has been interrupted...");
    dateWhenBufferEmptied = NSDate.date;
    playableWhenBufferEmptied = self.currentPlayable; 
}

- (void) didEndBufferInterruption {
    // make sure we don't resume anything that didn't need to resumed
    if (!dateWhenBufferEmptied || !playableWhenBufferEmptied) { return; }
    NSTimeInterval intervalSinceInterrupt = [NSDate.date timeIntervalSinceDate:dateWhenBufferEmptied];
    float interruptLimit = self.interruptResumeTimeLimit;
    PRXLog(@"Reachability returned from interruption after %f seconds. User limit is %f seconds.", intervalSinceInterrupt, interruptLimit);
    
    if (interruptLimit < 0
        || (intervalSinceInterrupt <= interruptLimit)) {
        PRXLog(@"Resuming playback after interrupt; limit not surpassed.");
        if (self.currentPlayable && [self.currentPlayable isEqualToPlayable:playableWhenBufferEmptied]) {
            [self reloadAndPlayPlayable:playableWhenBufferEmptied];
        } else {
            PRXLog(@"user has moved to a different playable after buffer emptying");
        }
    }
    dateWhenBufferEmptied = nil;
}

#pragma mark Audio Session Interruption

- (void)audioSessionInterruption:(NSNotification*)notification {
    if ([notification.userInfo[AVAudioSessionInterruptionTypeKey] isEqual:@(AVAudioSessionInterruptionTypeBegan)]) {
        [self audioSessionDidBeginInterruption:notification];
    } else if ([notification.userInfo[AVAudioSessionInterruptionTypeKey] isEqual:@(AVAudioSessionInterruptionTypeEnded)]) {
        [self audioSessionDidEndInterruption:notification];
    }
}

- (void)audioSessionDidBeginInterruption:(NSNotification*)notification {
    PRXLog(@"Audio session has been interrupted...");
    rateWhenAudioSessionDidBeginInterruption = self.player.rate;
    dateWhenAudioSessionDidBeginInterruption = NSDate.date;
}

- (void)audioSessionDidEndInterruption:(NSNotification*)notification {
    NSTimeInterval intervalSinceInterrupt = [NSDate.date timeIntervalSinceDate:dateWhenAudioSessionDidBeginInterruption];
    float interruptLimit = self.interruptResumeTimeLimit;
    PRXLog(@"[KRT][Audio] Audio session has returned from interruption after %f seconds. User limit is %f seconds.", intervalSinceInterrupt, interruptLimit);
    
    if (rateWhenAudioSessionDidBeginInterruption > 0.0f) {
        if (interruptLimit < 0
            || (intervalSinceInterrupt <= interruptLimit)) {
            PRXLog(@"[Resuming playback after interrupt; limit not surpassed.");
            self.player.rate = rateWhenAudioSessionDidBeginInterruption;
        }
    }
    
    rateWhenAudioSessionDidBeginInterruption = CGFLOAT_MIN;
    dateWhenAudioSessionDidBeginInterruption = nil;
}

- (NSTimeInterval) interruptResumeTimeLimit;
{
    return 300;
}

#pragma mark - Remote control

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (BOOL)becomeFirstResponder {
	[super becomeFirstResponder];
	return YES;
}

- (NSDictionary*)MPNowPlayingInfoCenterNowPlayingInfo {
    NSMutableDictionary *info;
    if (self.currentPlayable && self.currentPlayable.mediaItemProperties) {
        info = self.currentPlayable.mediaItemProperties.mutableCopy;
    } else {
        info = [NSMutableDictionary dictionaryWithCapacity:10];
    }
    if (!info[MPMediaItemPropertyArtist]) { 
        info[MPMediaItemPropertyArtist] = [self defaultNowPlayingArtist];
    }
    
    float _playbackDuration = self.currentPlayerItem ? CMTimeGetSeconds(self.currentPlayerItem.duration) : 0.0f;
    NSNumber* playbackDuration = @(_playbackDuration);
    info[MPMediaItemPropertyPlaybackDuration] = playbackDuration;
    
    float _elapsedPlaybackTime = self.currentPlayerItem ? CMTimeGetSeconds(self.currentPlayerItem.currentTime) : 0.0f;
    NSNumber* elapsedPlaybackTime = @(_elapsedPlaybackTime);
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedPlaybackTime;
    
            
    NSArray* metadata = self.player.currentItem.asset.commonMetadata;
    NSArray* artworkMetadata = [AVMetadataItem metadataItemsFromArray:metadata
                                                              withKey:AVMetadataCommonKeyArtwork
                                                             keySpace:AVMetadataKeySpaceCommon];
    if (artworkMetadata.count > 0) {
        AVMetadataItem* artworkMetadataItem = artworkMetadata[0];
        
        UIImage* artworkImage = [UIImage imageWithData:artworkMetadataItem.value[@"data"]];
        MPMediaItemArtwork* artwork = [[MPMediaItemArtwork alloc] initWithImage:artworkImage];
        
        info[MPMediaItemPropertyArtwork] = artwork;
    }
    
    return info; 
}

- (NSString *)defaultNowPlayingArtist {
    return @"PRXAudioPlayer"; 
}

- (void)setMPNowPlayingInfoCenterNowPlayingInfo {
    MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = self.MPNowPlayingInfoCenterNowPlayingInfo;
}

- (void)remoteControlReceivedWithEvent:(UIEvent*)event {
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
    [self audioSessionDidBeginInterruption:nil]; 
}

- (void)endInterruption {
    [[AVAudioSession sharedInstance] setActive:YES];
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [self audioSessionDidEndInterruption:nil];
}

- (void)endInterruptionWithFlags:(NSUInteger)flags {
    [self endInterruption];
}

- (void)inputIsAvailableChanged:(BOOL)isInputAvailable {
    
}

@end
