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

NSString * const PRXPlayerChangeNotification = @"PRXPlayerChangeNotification";
NSString * const PRXPlayerTimeIntervalNotification = @"PRXPlayerTimeIntervalNotification";
NSString * const PRXPlayerLongTimeIntervalNotification = @"PRXPlayerLongTimeIntervalNotification";

NSString * const PRXPlayerReachabilityPolicyPreventedPlayback = @"PRXPlayerReachabilityPolicyPreventedPlayback";

static const char *periodicTimeObserverQueueLabel = "PRXPlayerPeriodicTimeObserverQueueLabel";

@implementation PRXPlayer

+ (instancetype)sharedPlayer {
  static dispatch_once_t predicate;
  static id _instance = nil;

  dispatch_once(&predicate, ^{
    _instance = self.new;
  });

  return _instance;
}

+ (dispatch_queue_t)sharedQueue {
  static dispatch_queue_t sharedQueue;
  static dispatch_once_t onceToken;

  dispatch_once(&onceToken, ^{
    sharedQueue = dispatch_queue_create(periodicTimeObserverQueueLabel, DISPATCH_QUEUE_SERIAL);
  });

  return sharedQueue;
}

static void * const PRXPlayerItemContext = (void*)&PRXPlayerItemContext;
static void * const PRXPlayerAVPlayerContext = (void*)&PRXPlayerAVPlayerContext;
static void * const PRXPlayerAVPlayerStatusContext = (void*)&PRXPlayerAVPlayerStatusContext;
static void * const PRXPlayerAVPlayerRateContext = (void*)&PRXPlayerAVPlayerRateContext;
static void * const PRXPlayerAVPlayerErrorContext = (void*)&PRXPlayerAVPlayerErrorContext;
static void * const PRXPlayerAVPlayerCurrentItemContext = (void*)&PRXPlayerAVPlayerCurrentItemContext;
static void * const PRXPlayerAVPlayerCurrentItemStatusContext = (void*)&PRXPlayerAVPlayerCurrentItemStatusContext;
static void * const PRXPlayerAVPlayerCurrentItemBufferEmptyContext = (void*)&PRXPlayerAVPlayerCurrentItemBufferEmptyContext;

- (id)init {
  self = [super init];
  if (self) {
    NSKeyValueObservingOptions options = (NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld);

//    [self addObserver:self forKeyPath:@"player" options:options context:PRXPlayerAVPlayerContext];
    [self addObserver:self forKeyPath:@"playerItem" options:options context:PRXPlayerItemContext];

    _reach = [Reachability reachabilityWithHostname:@"www.google.com"];
    previousReachabilityStatus = -1;
    [self.reach startNotifier];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityDidChange:)
                                                 name:kReachabilityChangedNotification
                                               object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(audioSessionInterruption:)
                                               name:AVAudioSessionInterruptionNotification
                                             object:nil];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(audioSessionRouteChange:)
                                               name:AVAudioSessionRouteChangeNotification
                                             object:nil];
  }
  return self;
}

- (void)setDelegate:(id<PRXPlayerDelegate>)delegate {
  _delegate = delegate;
}

- (void)setPlayer:(AVPlayer *)player {
  // If there's an existing player we want to stop observing it
  // before changing to the new one
  @synchronized(_player) {
    dispatch_async(self.class.sharedQueue, ^{
      if (self.player) {
        NSLog(@"Stopping to observe AVPlayer");
        
        [self.player removeObserver:self forKeyPath:@"currentItem"];
        [self.player removeObserver:self forKeyPath:@"status"];
        [self.player removeObserver:self forKeyPath:@"rate"];
        [self.player removeObserver:self forKeyPath:@"error"];
        
        if (playerPeriodicTimeObserver) {
          [self.player removeTimeObserver:playerPeriodicTimeObserver];
          playerPeriodicTimeObserver = nil;
        }
        
        if (playerSoftEndBoundaryTimeObserver) {
          [self.player removeTimeObserver:playerSoftEndBoundaryTimeObserver];
          playerSoftEndBoundaryTimeObserver = nil;
        }
        
        if (playerPlaybackStartBoundaryTimeObserver) {
          [self.player removeTimeObserver:playerPlaybackStartBoundaryTimeObserver];
          playerPlaybackStartBoundaryTimeObserver = nil;
        }
      }
      
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        _player = player;
        
        if (player) {
          NSKeyValueObservingOptions options = (NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld);
          
          [self.player addObserver:self forKeyPath:@"currentItem" options:options context:PRXPlayerAVPlayerCurrentItemContext];
          
          [self.player addObserver:self forKeyPath:@"status" options:options context:PRXPlayerAVPlayerStatusContext];
          [self.player addObserver:self forKeyPath:@"rate" options:options context:PRXPlayerAVPlayerRateContext];
          [self.player addObserver:self forKeyPath:@"error" options:options context:PRXPlayerAVPlayerRateContext];
          
          __block id _self = self;
          
          playerPeriodicTimeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(1, 1000) queue:self.class.sharedQueue usingBlock:^(CMTime time) {
            [_self didObservePeriodicTimeChange:time];
          }];
          
          // when using playerWithPlayerItem: the player will come with an item, and the
          // current item context wont actually "change"
          if (self.player.currentItem) {
            NSLog(@"AVPlayer arrived with a current playerItem; treating it like an observed change");
            // don't forward the change, because it's not the change of the item
            [self mediaPlayerCurrentItemDidChange:nil];
          }
          
          [self postGeneralChangeNotification];
        }
      });
    });
  }
}

- (void)setPlayerItem:(id<PRXPlayerItem>)playerItem {
  // If setting to anything other than current PlayerItem
  // now is a good time to silence any existing playback
  if (![playerItem isEqualToPlayerItem:self.playerItem]) {
    self.player.rate = 0.0f;
  }

  ignoreTimeObservations = YES;
  _playerItem = playerItem;

  // Setting the playerItem to nil is the same as calling stop,
  // everything should get dumped;
  if (!playerItem && self.player) {
    [self.player replaceCurrentItemWithPlayerItem:nil];
    NSLog(@"Tearing down existing AVPlayer");
    self.player = nil;
  }
}

#pragma mark - Properties

- (NSTimeInterval)buffer {
  // TODO this should probably check for asset parity
  if (self.player.currentItem) {
    CMTimeRange tr;
    [self.player.currentItem.loadedTimeRanges.lastObject getValue:&tr];

    CMTime duration = tr.duration;
    return MAX(0.0f, CMTimeGetSeconds(duration));
  }

  return 0.0f;
}

- (PRXPlayerState)state {
  if (!self.playerItem) {
    return PRXPlayerStateEmpty;
  }

  AVAsset *playerAssset = self.player.currentItem.asset;
  AVAsset *itemAsset = self.playerItemAsset;

  BOOL isPlayerAssetURLAsset = [playerAssset isKindOfClass:AVURLAsset.class];
  BOOL isItemAssetURLAsset = [itemAsset isKindOfClass:AVURLAsset.class];

  BOOL haveAssetParity = (isItemAssetURLAsset && isPlayerAssetURLAsset && [((AVURLAsset *)itemAsset).URL isEqual:((AVURLAsset *)playerAssset).URL] ? YES : NO);

  if (!haveAssetParity
      && [self allowsLoadingOfAsset:itemAsset]) {
    // We can assume that the current asset (asset of the current PlayerItem) is "loading" if
    // it's not the asset that is currently in the player, and the reachability policy allows
    // it be loaded
    return PRXPlayerStateLoading;
  } else if (haveAssetParity
             && dateAtAudioPlaybackInterruption) {
    return PRXPlayerStateWaiting;
  } else if (haveAssetParity
             && self.player.currentItem
             && self.player.currentItem.status == AVPlayerStatusReadyToPlay) {
    // If we have asset parity and the AVPlayer's asset is ready, we can consider the PRXPlayer
    // state to be ready as well
    return PRXPlayerStateReady;
  } else if (haveAssetParity) {
    // This likely isn't accurate...
    //
    return PRXPlayerStateBuffering;
  }

  // If we get here we don't really know what's going on with the player and we should feel bad
  return PRXPlayerStateUnknown;
}

// this will go away
- (NSDate *)dateAtAudioPlaybackInterruption {
  return dateAtAudioPlaybackInterruption;
}

#pragma mark - Indifferent controls

- (void)play {
  holdPlayback = NO;
  dateAtAudioPlaybackInterruption = nil;

  // If the current player item isn't ready, nothing good can happen from trying
  // to start playback
  if (!self.player.currentItem
      || (self.player.currentItem && self.player.currentItem.status != AVPlayerStatusReadyToPlay)) {
    NSLog(@"Asked to play but no item is ready; if something it loading there is no hold so it will start");
    return;
  }

  // If the current player asset doesn't match the current item asset
  // simply starting playback is almost certainly unexpected behavior
  if ([self.playerItemAsset isKindOfClass:AVURLAsset.class]
      && [self.player.currentItem.asset isKindOfClass:AVURLAsset.class]) {
    AVURLAsset *currentAsset = (AVURLAsset *)self.player.currentItem.asset;
    AVURLAsset *itemAsset = (AVURLAsset *)self.playerItemAsset;

    if (![currentAsset.URL isEqual:itemAsset.URL]) {
      NSLog(@"Current item does not match the loaded item, starting playback now would likely result in unexpected behavior");
      return;
    }
  }

  if (self.player.rate == 0.0f
      || (self.player.rate != 0.0f && self.player.rate != self.rateForPlayback)) {
    self.player.rate = self.rateForPlayback;
  }
}

- (void)pause {
  if (self.player.rate != 0.0f) {
    self.player.rate = 0.0f;
  }

  holdPlayback = YES;
  dateAtAudioPlaybackInterruption = nil;
}

- (void)toggle {
  (self.player.rate == 0.0f) ? [self play] : [self pause];
}

- (void)toggleOrCancel {
  if (self.state == PRXPlayerStateLoading ||
      self.state == PRXPlayerStateBuffering ||
      self.state == PRXPlayerStateWaiting) {
    [self pause];
  } else {
    [self toggle];
  }
}

- (void)stop {
  self.playerItem = nil;
}

#pragma mark - Remote control

- (BOOL)canBecomeFirstResponder {
  return YES;
}

- (BOOL)becomeFirstResponder {
	return YES;
}

- (NSDictionary *)MPNowPlayingInfoCenterNowPlayingInfo {
  NSMutableDictionary *info = NSMutableDictionary.dictionary;

  if ([self.playerItem respondsToSelector:@selector(mediaItemProperties)]) {
    [info setValuesForKeysWithDictionary:self.playerItem.mediaItemProperties];
  }

  // We'll use the asset metadata (eg ID3 tags) as default values for any properties
  // that didnt get set explicitly by the current PRXPlayerItem
  NSArray* metadata = self.player.currentItem.asset.commonMetadata;

  // Reporting times when we don't have a duration can get messy
  if (self.player.currentItem.duration.value > 0) {
    if (!info[MPMediaItemPropertyPlaybackDuration]) {
      float _playbackDuration = self.player.currentItem ? CMTimeGetSeconds(self.player.currentItem.duration) : 0.0f;
      NSNumber* playbackDuration = @(_playbackDuration);
      info[MPMediaItemPropertyPlaybackDuration] = playbackDuration;
    }

    if (!info[MPNowPlayingInfoPropertyElapsedPlaybackTime]) {
      float _elapsedPlaybackTime = self.player.currentItem ? CMTimeGetSeconds(self.player.currentItem.currentTime) : 0.0f;
      NSNumber* elapsedPlaybackTime = @(_elapsedPlaybackTime);
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedPlaybackTime;
    }
  }

  if (!info[MPNowPlayingInfoPropertyPlaybackRate]) {
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(self.rateForPlayback);
  }

  if (!info[MPMediaItemPropertyArtwork]) {
    NSArray* artworkMetadata = [AVMetadataItem metadataItemsFromArray:metadata
                                                              withKey:AVMetadataCommonKeyArtwork
                                                             keySpace:AVMetadataKeySpaceCommon];
    if (artworkMetadata.count > 0) {
      AVMetadataItem* artworkMetadataItem = artworkMetadata[0];
      UIImage* artworkImage;

      if ([artworkMetadataItem.value respondsToSelector:@selector(objectForKeyedSubscript:)]) {
        artworkImage = [UIImage imageWithData:artworkMetadataItem.value[@"data"]];
      } else if ([artworkMetadataItem.value isKindOfClass:NSData.class]) {
        artworkImage = [UIImage imageWithData:artworkMetadataItem.dataValue];
      }

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

- (void)publishMPNowPlayingInfoCenterNowPlayingInfo {
  NSLog(@"Publishing media item properties to MPNowPlayingInfoCenter");
  MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = self.MPNowPlayingInfoCenterNowPlayingInfo;
}

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
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
      [self toggle];
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

#pragma mark - Target playback rates

- (float)rateForFilePlayback {
  if ([self.delegate respondsToSelector:@selector(filePlaybackRateForPlayer:)]) {
    return [self.delegate filePlaybackRateForPlayer:self];
  }

  return 1.0f;
}

- (float)rateForPlayback {
  // It's dangerous to try to play to play unbounded (eg non-file, ie streams)
  // assets faster than 1x, as it will almost always play at 1x anyway

  return (CMTIME_IS_INDEFINITE(self.player.currentItem.duration) ? 1.0f : self.rateForFilePlayback);
}

#pragma mark - Reachablity

- (BOOL)allowsPlaybackViaWWAN {
  if ([self.delegate respondsToSelector:@selector(playerAllowsPlaybackViaWWAN:)]) {
    return [self.delegate playerAllowsPlaybackViaWWAN:self];
  }

  return YES;
}

- (BOOL)allowsLoadingOfAsset:(AVAsset *)asset {
  self.reach.reachableOnWWAN = self.allowsPlaybackViaWWAN;
  BOOL isAssetLocal = NO;

  if ([asset isKindOfClass:AVURLAsset.class]) {
    AVURLAsset *_asset = (AVURLAsset *)asset;

    if (_asset.URL.isFileURL) {
      isAssetLocal = YES;
    }
  }

  if (!self.reach.isReachable && !isAssetLocal) {
    NSLog(@"Reachability policy doesn't allow for WWAN playback of remote assets; tracks will not be loaded");
    [NSNotificationCenter.defaultCenter postNotificationName:PRXPlayerReachabilityPolicyPreventedPlayback object:self];
    return NO;
  } else {
    NSLog(@"Reachability policy allows for playback under current conditions: Local file: %i, Reach: %@", isAssetLocal, self.reach.currentReachabilityString);
    return YES;
  }
}

#pragma mark - Loading assets

- (AVAsset *)playerItemAsset {
  AVAsset *asset = self.playerItem.playerAsset;

  if ([self.delegate respondsToSelector:@selector(player:assetForPlayerItem:)]) {
    asset = [self.delegate player:self assetForPlayerItem:self.playerItem];
  }

  return asset;
}

- (void)loadTracksForAsset:(AVAsset *)asset {
  if (![self allowsLoadingOfAsset:asset]) {
    return;
  }
  
  ignoreTimeObservations = YES;

  static NSString *AVKeyAssetTracks = @"tracks";

  NSLog(@"Attempting to load tracks for asset");
  [asset loadValuesAsynchronouslyForKeys:@[ AVKeyAssetTracks ] completionHandler:^{
    NSLog(@"Done trying to load tracks for asset...");

    dispatch_async(dispatch_get_main_queue(), ^{
      NSError *error;
      AVKeyValueStatus status = [asset statusOfValueForKey:AVKeyAssetTracks error:&error];

      if (status == AVKeyValueStatusLoaded) {
        NSLog(@"...Loaded tracks for asset, passing to AVPlayer if necessary");

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          // TODO clean up these if/elses
          if (!self.playerItem) {
            NSLog(@"PlayerItem was removed before tracks could load, so they're being ignored");
            return;
          } else if ([asset isKindOfClass:AVURLAsset.class] && [self.playerItemAsset isKindOfClass:AVURLAsset.class]) {
            AVURLAsset *urlAsset = (AVURLAsset *)asset;
            AVURLAsset *itemURLAsset = (AVURLAsset *)self.playerItemAsset;

            if (![urlAsset.URL.absoluteString isEqualToString:itemURLAsset.URL.absoluteString]) {
              NSLog(@"PlayerItem asset no longer matches this asset, so the loaded tracks are being ignored");
              return;
            }
          }

          AVPlayerItem *playerItem = [AVPlayerItem playerItemWithAsset:asset];

          // Using replaceCurrentItemWithPlayerItem: was problematic
          // but may be more better if the issues are fixed
          NSLog(@"Setting up a new new AVPlayer");
          self.player = [AVPlayer playerWithPlayerItem:playerItem];
        });
      } else {
        BOOL _hold = holdPlayback;
        NSLog(@"...Failed to load tracks for asset %@", asset);
        holdPlayback = YES; // until there's something better to do; may actually be worth stopping

        if ([self.delegate respondsToSelector:@selector(player:failedToLoadTracksForAsset:holdPlayback:)]) {
          [self.delegate player:self failedToLoadTracksForAsset:asset holdPlayback:_hold];
        }

        // TODO
        // loading the tracks using a player url asset is more reliable and has already been tried
        // by the time we get here.  but if it fails we can still try to set the player item directly.
        //  self.currentPlayerItem = [AVPlayerItem playerItemWithURL:self.currentPlayable.audioURL];
      }
    });
  }];
}

#pragma mark - Routing observations

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
  if (context == &PRXPlayerAVPlayerContext) {
    NSLog(@"Observed AVPlayer change");
    [self mediaPlayerDidChange:change];
    return;
  } else if (context == &PRXPlayerItemContext) {
    NSLog(@"Observed PRXPlayerItem change");
    [self playerItemDidChange:change];
    return;
  } else if (context == &PRXPlayerAVPlayerCurrentItemContext) {
    NSLog(@"Observed AVPlayer currentItem change");
    [self mediaPlayerCurrentItemDidChange:change];
    return;
  } else if (context == &PRXPlayerAVPlayerStatusContext) {
    // TODO figure out a way to trigger this
    NSLog(@"PRXPlayerAVPlayerStatusContext");
    return;
  } else if (context == &PRXPlayerAVPlayerRateContext) {
    NSLog(@"Observed AVPlayer rate change");
    [self mediaPlayerRateDidChange:change];
    return;
  } else if (context == &PRXPlayerAVPlayerErrorContext) {
    // TODO I dont think this is actually worth observing, since the player
    // will never recover from an error, and the value is only worth
    // checking after a status change, which is observed separately
    NSLog(@"PRXPlayerAVPlayerErrorContext");
    [self mediaPlayerErrorDidChange:change];
    return;
  } else if (context == &PRXPlayerAVPlayerCurrentItemStatusContext) {
    NSLog(@"Observed player item status change");
    [self mediaPlayerCurrentItemStatusDidChange:change];
    return;
  } else if (context == &PRXPlayerAVPlayerCurrentItemBufferEmptyContext) {
    NSLog(@"Observed player item buffer state change");
    [self mediaPlayerCurrentItemBufferEmptied:change];
    return;
  }

  [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
  return;
}

#pragma mark - Responding to observations

- (void)playerItemDidChange:(NSDictionary *)change {
  NSUInteger valueChangeKind = [change[NSKeyValueChangeKindKey] integerValue];
  id newValue = change[NSKeyValueChangeNewKey];
  id oldValue = change[NSKeyValueChangeOldKey];

  if ([self.delegate respondsToSelector:@selector(player:playerItemDidChange:)]) {
    [self.delegate player:self playerItemDidChange:change];
  }

  [self postGeneralChangeNotification];

  if (valueChangeKind == NSKeyValueChangeSetting && [newValue conformsToProtocol:@protocol(PRXPlayerItem)]) {
    NSLog(@"PRXPlayerItem was set");

    id<PRXPlayerItem> newPlayerItem = newValue;

    // most prxplayer properties can/should be reset somewhere in here
    //    dateAtAudioPlaybackInterruption = nil; //this really can't happen here

    //
    // Nothing can happen after these checks; most call async methods
    // and we need to wait for the results
    //

    // If there was no previous valid PlayerItem, we can always load the new one
    BOOL previousPlayerItemDidNotConformToProtocol = ![oldValue conformsToProtocol:@protocol(PRXPlayerItem)];

    ignoreTimeObservations = YES;
    
    if (previousPlayerItemDidNotConformToProtocol) {
      NSLog(@"No previous player item was set; no reason not to load tracks for new one");
      [self loadTracksForAsset:self.playerItemAsset];
      return;
    } else {
      BOOL newPlayerItemHasNoURLAssetForComparison = ![newPlayerItem.playerAsset isKindOfClass:AVURLAsset.class];

      if (newPlayerItemHasNoURLAssetForComparison) {
        NSLog(@"New asset isn't a URL asset, so we can't make any checks; just load the tracks");
        [self loadTracksForAsset:self.playerItemAsset];
        return;
      } else {
        id<PRXPlayerItem> oldPlayerItem = oldValue;
        AVURLAsset *newURLAsset = (AVURLAsset *)newPlayerItem.playerAsset;

        //
        // Knowing the new PlayerItem asset is a URL asset lets us be smart
        // about some specific situations
        //

        // if the new and old items are the same, we're probably dealing with a case
        // where the PlayerItem's asset resource changed from local to remote.
        // Since old and new are the same, checking for a change in that object's
        // asset would always be false, so we should check against the asset
        // actually loaded into the player
        // (this only can be checked if the current asset is a URL asset)
        if ([oldPlayerItem isEqualToPlayerItem:newPlayerItem]
            && [self.player.currentItem.asset isKindOfClass:AVURLAsset.class]) {
          AVURLAsset *currentAsset = (AVURLAsset *)self.player.currentItem.asset;

          if (![currentAsset.URL isEqual:newURLAsset.URL]) {
            NSLog(@"New PlayerItem matches currentPlayer item, but URLs differ. Resource likely changed; loading tracks");
            // This will not seemlessly transition between resources unless you are maintaning
            // position state on the PRXPlayerItem, which will be used after the tracks load.
            // Otherwise each transition will restart from the beginning.
            [self loadTracksForAsset:self.playerItemAsset];
            return;
          } else {
            // Old and new PlayerItem were equal, and the new item's asset
            // matches the currently loaded asset,
            // just make sure it's playing/holding as requested
            NSLog(@"New PlayerItem matches current PlayerItem exactly. No reason to load, just deal with playback");
            [self bar];
            return;
          }
        } else if ([oldPlayerItem.playerAsset isKindOfClass:AVURLAsset.class]) {
          AVURLAsset *oldURLAsset = (AVURLAsset *)oldPlayerItem.playerAsset;

          // If the new and old PlayerItems are not the same, but their
          // asset URLs are, we can't assume it's a remote/local switchover,
          // and there's no need to reload the already loaded tracks, so
          // just make sure it's playing/holding as requested
          if ([oldURLAsset.URL isEqual:newURLAsset.URL]) {
            NSLog(@"PlayerItem changed, but asset resource (URL) did not. No reason to load, just deal with playback");
            [self bar];
            return;
          } else {
            NSLog(@"PlayerItems and Asset URLs have changed; load tracks for new PlayerItem");
            [self loadTracksForAsset:self.playerItemAsset];
            return;
          }
        } else {
          // PlayerItem changed but old item's asset isn't a URL asset, so we
          // can't make any good checks; just load the tracks
          NSLog(@"Couldn't compare new PlayerItem with old asset, so load its tracks");
          [self loadTracksForAsset:self.playerItemAsset];
          return;
        }
      }
    }
  }
}

- (void)mediaPlayerDidChange:(NSDictionary *)change {
  NSUInteger valueChangeKind = [change[NSKeyValueChangeKindKey] integerValue];

  id new = change[NSKeyValueChangeNewKey];

  // Unless the situation changes, we only care about times when the AVPlayer gets set to a valid player
  if (valueChangeKind == NSKeyValueChangeSetting && [new isKindOfClass:AVPlayer.class]) {
    NSLog(@"Starting to observe AVPlayer");

    @synchronized(self.player) {
      NSKeyValueObservingOptions options = (NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld);

      [self.player addObserver:self forKeyPath:@"currentItem" options:options context:PRXPlayerAVPlayerCurrentItemContext];

      [self.player addObserver:self forKeyPath:@"status" options:options context:PRXPlayerAVPlayerStatusContext];
      [self.player addObserver:self forKeyPath:@"rate" options:options context:PRXPlayerAVPlayerRateContext];
      [self.player addObserver:self forKeyPath:@"error" options:options context:PRXPlayerAVPlayerRateContext];

      __block id _self = self;
      
      dispatch_async(self.class.sharedQueue, ^{
        if (playerSoftEndBoundaryTimeObserver) {
          [self.player removeTimeObserver:playerSoftEndBoundaryTimeObserver];
          playerSoftEndBoundaryTimeObserver = nil;
        }
        
        if (playerPeriodicTimeObserver) {
          [self.player removeTimeObserver:playerPeriodicTimeObserver];
          playerPeriodicTimeObserver = nil;
        }
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          playerPeriodicTimeObserver = [self.player addPeriodicTimeObserverForInterval:CMTimeMakeWithSeconds(1, 1000) queue:self.class.sharedQueue usingBlock:^(CMTime time) {
            [_self didObservePeriodicTimeChange:time];
          }];
          
          // when using playerWithPlayerItem: the player will come with an item, and the
          // current item context wont actually "change"
          if (self.player.currentItem) {
            NSLog(@"AVPlayer arrived with a current playerItem; treating it like an observed change");
            // don't forward the change, because it's not the change of the item
            [self mediaPlayerCurrentItemDidChange:nil];
          }
          
          [self postGeneralChangeNotification];
        });
      });
    }
  }

  [self postGeneralChangeNotification];
}

- (void)mediaPlayerRateDidChange:(NSDictionary *)change {
  if ([change[NSKeyValueChangeNewKey] isKindOfClass:NSClassFromString(@"NSError")]) { return; }
  float newValue = [change[NSKeyValueChangeNewKey] floatValue];

  // When the rate becomes non-zero we should check to make sure the
  // NowPlayingInfo's rate is correct, in case the target playback rate
  // has changed since it was last published, and republish if necessary
  if (newValue != 0.0) {
    NSDictionary *nowPlayingInfo = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    NSNumber *_playbackRate = nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate];

    if (_playbackRate && ![_playbackRate isEqual:NSNull.null]) {
      float playbackRate = _playbackRate.floatValue;

      if (newValue != playbackRate) {
        NSLog(@"Target playback rate appears to have changed from %f to %f", playbackRate, newValue);
        [self publishMPNowPlayingInfoCenterNowPlayingInfo];
      }
    }
  }

  if ([self.delegate respondsToSelector:@selector(player:rateDidChange:)]) {
    [self.delegate player:self rateDidChange:change];
  }

  [self postGeneralChangeNotification];
}

- (void)mediaPlayerErrorDidChange:(NSDictionary *)change {
}

- (void)mediaPlayerCurrentItemDidChange:(NSDictionary *)change {
  // will not get a change when called indirectly after a AVPlayer change

  AVPlayerItem *playerItem = self.player.currentItem;

  if (playerItem) {
    NSLog(@"Starting to observe AVPlayer's currentItem");

    NSKeyValueObservingOptions options = (NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld);

    [playerItem addObserver:self forKeyPath:@"status" options:options context:PRXPlayerAVPlayerCurrentItemStatusContext];
    [playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:options context:PRXPlayerAVPlayerCurrentItemBufferEmptyContext];

    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemTimeJumpedNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(mediaPlayerCurrentItemDidPlayToEndTime:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:playerItem];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(mediaPlayerCurrentItemDidJumpTime:)
                                                 name:AVPlayerItemTimeJumpedNotification
                                               object:playerItem];

    // Sometimes I think this change doesn't get observed until after
    // after the status has already changed, so we need to invoke some
    // handlers manually
    if (playerItem.status != AVPlayerStatusUnknown) {
      NSLog(@"Newly set AVPlayerItem arrived with a meaningful status; handling appropriately");

      if (playerItem.status == AVPlayerStatusReadyToPlay) {
        [self mediaPlayerCurrentItemDidBecomeReadyToPlay];
      } else if (playerItem.status == AVPlayerStatusFailed) {
        [self mediaPlayerCurrentItemFailedToBecomeReadyToPlay];
      }
    }
  }
}

- (void)mediaPlayerCurrentItemStatusDidChange:(NSDictionary *)change {
  NSUInteger valueChangeKind = [change[NSKeyValueChangeKindKey] integerValue];

  if (valueChangeKind == NSKeyValueChangeSetting) {
    id _new = change[NSKeyValueChangeNewKey];
    id _old = change[NSKeyValueChangeOldKey];

    // Only if an actual change happened.
    if (![_new isEqual:_old]) {
      if (self.player.currentItem.status == AVPlayerStatusReadyToPlay) {
        NSLog(@"Item status is ReadyToPlay");
        [self mediaPlayerCurrentItemDidBecomeReadyToPlay];
      } else if (self.player.currentItem.status == AVPlayerStatusFailed) {
        NSLog(@"Item status is failed: %@", self.player.currentItem.error);
        // force this with an HTTP200 .m3u that contains an HTTP404
        [self mediaPlayerCurrentItemFailedToBecomeReadyToPlay];
      } else {
        NSLog(@"Item status is not ready or failed: %li", (long)self.player.currentItem.status);
      }
    }
  }

  if ([self.delegate respondsToSelector:@selector(player:currentItemStatusDidChange:)]) {
    [self.delegate player:self currentItemStatusDidChange:change];
  }

  [self postGeneralChangeNotification];
}

- (void)mediaPlayerCurrentItemDidBecomeReadyToPlay {
  [self publishMPNowPlayingInfoCenterNowPlayingInfo];

  if (self.player.currentItem.duration.value > 0) {
    Float64 duration = CMTimeGetSeconds(self.player.currentItem.duration);

    Float64 progress = 0.95f;

    if ([self.delegate respondsToSelector:@selector(softEndBoundaryProgressForPlayer:)]) {
      progress = [self.delegate softEndBoundaryProgressForPlayer:self];
    }

    int64_t boundaryTime = (duration * progress);
    CMTime boundary = CMTimeMakeWithSeconds(boundaryTime, 10);

    NSValue* _boundary = [NSValue valueWithCMTime:boundary];

    __block id _self = self;

    dispatch_async(self.class.sharedQueue, ^{
      if (playerSoftEndBoundaryTimeObserver) {
        [self.player removeTimeObserver:playerSoftEndBoundaryTimeObserver];
        playerSoftEndBoundaryTimeObserver = nil;
      }
      
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"Adding soft end boundary observer: %@s (%f)", @(CMTimeGetSeconds(boundary)), progress);
        playerSoftEndBoundaryTimeObserver = [self.player addBoundaryTimeObserverForTimes:@[ _boundary ]
                                                                                   queue:self.class.sharedQueue
                                                                              usingBlock:^{
                                                                                [_self didObserveSoftBoundaryTime];
                                                                              }];

        [self bar];
      });
    });
  }
}

- (void)mediaPlayerCurrentItemFailedToBecomeReadyToPlay {
  NSUInteger _retryLimit = 3;

  if ([self.delegate respondsToSelector:@selector(retryLimitForPlayer:)]) {
    _retryLimit = [self.delegate retryLimitForPlayer:self];
  }

  if (retryCount < _retryLimit) {
    retryCount++;
    NSLog(@"Retry %lu of %lu", (unsigned long)retryCount, (unsigned long)_retryLimit);

    id<PRXPlayerItem> retryPlayerItem = self.playerItem;
    [self stop];
    self.playerItem = retryPlayerItem;
  } else {
    NSLog(@"Retries failed, stopping.");
    BOOL _hold = holdPlayback;
    [self stop];

    if ([self.delegate respondsToSelector:@selector(playerFailedToBecomeReadyToPlay:holdPlayback:)]) {
      [self.delegate playerFailedToBecomeReadyToPlay:self holdPlayback:_hold];
    }
  }
}

- (void)mediaPlayerCurrentItemBufferEmptied:(NSDictionary *)change {
  BOOL oldValue = [change[NSKeyValueChangeOldKey] boolValue];
  BOOL newValue = [change[NSKeyValueChangeNewKey] boolValue];

  if (oldValue != newValue && self.playerItem) {
    if (newValue) {
      NSLog(@"Buffer went from not empty to empty...");

      if ([self.player.currentItem.asset isKindOfClass:AVURLAsset.class]
          && [[((AVURLAsset *)self.player.currentItem.asset) URL] isFileURL] ) {
        NSLog(@"...but was a local file. This isn't considered a problem; no need to restart.");
      } else if (!self.reach.isReachable) {
        NSLog(@"...and we don't have connectivity for a remote file/stream; flag for a restart when we do...");
        // TODO flag for retry
      } else {
        if (self.player.externalPlaybackActive) {
          NSLog(@"...still have connectivity, but AirPlay is borked, NOT trying again.");
        } else {
          NSLog(@"...but we still have connectivity, reloading remote files/streams to try again");
          [self reloadPlayerItemWithRemoteAsset:self.playerItem];
        }
      }
    } else {
      NSLog(@"Buffer went from empty to not empty");
    }
  }
}

- (void)mediaPlayerCurrentItemDidPlayToEndTime:(NSNotification *)notification {
  if ([self.delegate respondsToSelector:@selector(player:endTimeReachedForPlayerItem:)]) {
    [self.delegate player:self endTimeReachedForPlayerItem:notification.object];
  }
}

- (void)mediaPlayerCurrentItemDidJumpTime:(NSNotification *)notification {
  if (!ignoreTimeObservations) {
    // called when seeking and when setting rate >0
    [self publishMPNowPlayingInfoCenterNowPlayingInfo];
  }
}

- (void)didObservePeriodicTimeChange:(CMTime)time {
  if (ignoreTimeObservations) {
    NSLog(@"Ignoring out of sequence time change");
  } else {
    NSValue *time_v = [NSValue valueWithCMTime:time];
    NSDictionary *userInfo = @{ @"time": time_v };
    
    AVURLAsset *asset;
    
    [NSNotificationCenter.defaultCenter postNotificationName:PRXPlayerTimeIntervalNotification
                                                      object:self
                                                    userInfo:userInfo];
    
    if ([self.player.currentItem.asset isKindOfClass:AVURLAsset.class]) {
      asset = (AVURLAsset *)self.player.currentItem.asset;
      
      [NSNotificationCenter.defaultCenter postNotificationName:PRXPlayerTimeIntervalNotification
                                                        object:asset.URL.absoluteString
                                                      userInfo:userInfo];
    }
    
    if ([self.playerItem respondsToSelector:@selector(setPlayerTime:)]) {
      
      self.playerItem.playerTime = time;
    }
    
    if (fmodf(round(CMTimeGetSeconds(time)), 10.0f) == 9.0f) {
      [NSNotificationCenter.defaultCenter postNotificationName:PRXPlayerLongTimeIntervalNotification
                                                        object:self
                                                      userInfo:userInfo];
      
      if (asset) {
        [NSNotificationCenter.defaultCenter postNotificationName:PRXPlayerLongTimeIntervalNotification
                                                          object:asset.URL.absoluteString
                                                        userInfo:userInfo];
      }
    }
  }
}

- (void)didObserveSoftBoundaryTime {
  if (!ignoreTimeObservations) {
    if ([self.delegate respondsToSelector:@selector(player:softBoundaryTimeReachedForPlayerItem:)]) {
      [self.delegate player:self softBoundaryTimeReachedForPlayerItem:self.player.currentItem];
    }
    
    [self publishMPNowPlayingInfoCenterNowPlayingInfo];
  }
}

- (void)didObservePlaybackStartBoundaryTime {
  ignoreTimeObservations = NO;
  NSLog(@"[Player] No longer ignoring time observations");
  
  if (playerPlaybackStartBoundaryTimeObserver) {
    dispatch_async(self.class.sharedQueue, ^{
      [self.player removeTimeObserver:playerPlaybackStartBoundaryTimeObserver];
      playerPlaybackStartBoundaryTimeObserver = nil;
    });
  }
}

- (void)reachabilityDidChange:(NSNotification *)notification {
  Reachability *reach = notification.object;

  if (previousReachabilityStatus == -1) {
    NSLog(@"Reachability status became available, it is: %@", reach.currentReachabilityString);
  } else if (reach.currentReachabilityStatus != previousReachabilityStatus) {
    NSLog(@"Reachability changed from %@ to %@", previousReachabilityString, reach.currentReachabilityString);

    if (self.playerItem) {
      if (reach.currentReachabilityStatus == NotReachable) {
        NSLog(@"No longer have a network connection. Keeping app alive as long as possible to watch for reconnect.");
        [self keepAliveInBackground];
      } else if (reach.currentReachabilityStatus == ReachableViaWiFi) {
        NSLog(@"Connected to WiFi; reload remote files/streams (either to fix player failure, or reduce WWAN bandwidth)");
        [self reloadPlayerItemWithRemoteAsset:self.playerItem];
      } else if (reach.currentReachabilityStatus == ReachableViaWWAN
                 && previousReachabilityStatus == NotReachable) {
        NSLog(@"Connected to WWAN after losing connection; reload the player");
        [self reloadPlayerItemWithRemoteAsset:self.playerItem];
      } else if (reach.currentReachabilityStatus == ReachableViaWWAN
                 && previousReachabilityStatus == ReachableViaWiFi) {
        NSLog(@"Lost Wifi connection but maintained WWAN; reload the player to continue playback");
        [self reloadPlayerItemWithRemoteAsset:self.playerItem];
      }
    }
  } else {
    NSLog(@"Reachability status change was triggered, but the value didn't actually change");
  }

  previousReachabilityStatus = reach.currentReachabilityStatus;
  previousReachabilityString = reach.currentReachabilityString;
}

#pragma mark - Playback vector

- (void)loadPlayerItem:(id<PRXPlayerItem>)playerItem {
  holdPlayback = YES;
  self.playerItem = playerItem;
}

- (void)playPlayerItem:(id<PRXPlayerItem>)playerItem {
  holdPlayback = NO;
  self.playerItem = playerItem;
}

- (void)togglePlayerItem:(id<PRXPlayerItem>)playerItem orCancel:(BOOL)cancel {
  AVAsset *playerItemAsset = playerItem.playerAsset;

  if ([self.delegate respondsToSelector:@selector(player:assetForPlayerItem:)]) {
    playerItemAsset = [self.delegate player:self assetForPlayerItem:playerItem];
  }

  if (!cancel) {
    if ([playerItemAsset isKindOfClass:AVURLAsset.class]
        && [self.player.currentItem.asset isKindOfClass:AVURLAsset.class]
        && [((AVURLAsset *)self.player.currentItem.asset).URL.absoluteString isEqual:((AVURLAsset *)playerItemAsset).URL.absoluteString]
        && self.player.rate != 0.0f) {
      [self pause];
    } else {
      [self playPlayerItem:playerItem];
    }

    return;
  } else { // try to cancel

    if ((self.state == PRXPlayerStateLoading ||
         self.state == PRXPlayerStateBuffering ||
         self.state == PRXPlayerStateWaiting)) {
      [self stop];
    } else if ([playerItemAsset isKindOfClass:AVURLAsset.class]
        && [self.player.currentItem.asset isKindOfClass:AVURLAsset.class]
        && [((AVURLAsset *)self.player.currentItem.asset).URL isEqual:((AVURLAsset *)playerItemAsset).URL]
        && self.player.rate != 0.0f) {
      [self pause];
    } else {
      [self playPlayerItem:playerItem];
    }

    return;
  }

  if (cancel && (self.state == PRXPlayerStateLoading ||
                 self.state == PRXPlayerStateBuffering ||
                 self.state == PRXPlayerStateWaiting)) {
    [self pause];
  } else if ([playerItemAsset isKindOfClass:AVURLAsset.class]
      && [self.player.currentItem.asset isKindOfClass:AVURLAsset.class]
      && [((AVURLAsset *)self.player.currentItem.asset).URL isEqual:((AVURLAsset *)playerItemAsset).URL]
      && self.player.rate != 0.0f) {
    [self pause];
  } else {
    [self playPlayerItem:playerItem];
  }
}

- (void)togglePlayerItem:(id<PRXPlayerItem>)playerItem {
  [self togglePlayerItem:playerItem orCancel:NO];
}

- (void)reloadPlayerItem:(id<PRXPlayerItem>)playerItem {
  // reloading an item will lose the current time position unless it's being persisted
  // this is avoidable but not currently implemented
  NSLog(@"Reloading player item, holdPlayback is set to %i", holdPlayback);
  BOOL hold = holdPlayback;
  [self stop];
  holdPlayback = hold;
  self.playerItem = playerItem;
}

- (void)reloadPlayerItemWithRemoteAsset:(id<PRXPlayerItem>)playerItem {
  AVAsset *playerItemAsset = playerItem.playerAsset;

  if ([self.delegate respondsToSelector:@selector(player:assetForPlayerItem:)]) {
    playerItemAsset = [self.delegate player:self assetForPlayerItem:playerItem];
  }

  if ([playerItemAsset isKindOfClass:AVURLAsset.class]
      && ![[(AVURLAsset *)playerItemAsset URL] isFileURL]) {
    NSLog(@"Reloading PlayerItem with remote URL asset");
    [self reloadPlayerItem:playerItem];
  }
}

- (void)setupPlaybackStartBoundaryObserverCompletionHandler:(void (^)())completionHandler {
  if (self.player.currentItem) {
    
    dispatch_async(self.class.sharedQueue, ^{
      if (playerPlaybackStartBoundaryTimeObserver) {
        [self.player removeTimeObserver:playerPlaybackStartBoundaryTimeObserver];
        playerPlaybackStartBoundaryTimeObserver = nil;
      }
      
      AVPlayerItem *currentItem = self.player.currentItem;
      CMTime duration = currentItem.duration;
      
      if (CMTIME_IS_VALID(duration)) {
        // Boundary needs to be after playhead
        
        CMTime time = self.playerItem.playerTime;
        
        if (CMTimeCompare(time, kCMTimeZero) == 0
            || CMTIME_IS_INVALID(time)
            || CMTIME_IS_INDEFINITE(time)
            || CMTIME_IS_NEGATIVE_INFINITY(time)
            || CMTIME_IS_POSITIVE_INFINITY(time)) {
          time = kCMTimeZero;
        }
        
        CMTime boundaryTimePadding = CMTimeMake(1, 3);
        
        CMTime boundaryTime = CMTimeAdd(time, boundaryTimePadding);
        NSValue *boundaryTime_v = [NSValue valueWithCMTime:boundaryTime];
        
        __block id _self = self;
        
        playerPlaybackStartBoundaryTimeObserver = [self.player addBoundaryTimeObserverForTimes:@[ boundaryTime_v ]
                                                                                         queue:self.class.sharedQueue
                                                                                    usingBlock:^{
                                                                                      [_self didObservePlaybackStartBoundaryTime];
                                                                                    }];
        
        if (completionHandler) {
          completionHandler();
        }
      }
    });
  }
}

- (void)bar {
  if (self.player.currentItem.status != AVPlayerStatusReadyToPlay) {
    NSLog(@"Couldn't finalize playback because current player item wasn't ready to play");
  } else {
    
    [self setupPlaybackStartBoundaryObserverCompletionHandler:^{
      
      // If there was an audio interrupt
      if (dateAtAudioPlaybackInterruption) {
        NSTimeInterval intervalSinceInterrupt = [NSDate.date timeIntervalSinceDate:dateAtAudioPlaybackInterruption];
        
        NSLog(@"Appear to be recovering from an interrupt that's %fs old", intervalSinceInterrupt);
        
        NSTimeInterval limit = (60.0f * 4.0f);
        BOOL withinResumeTimeLimit = (limit < 0) || (intervalSinceInterrupt <= limit);
        
        if (!withinResumeTimeLimit) {
          NSLog(@"Internal playback request after an interrupt, but waited too long; exiting.");
          holdPlayback = YES;
        }
        
        dateAtAudioPlaybackInterruption = nil;
      }
      
      if ([self.playerItem respondsToSelector:@selector(playerTime)]) {
        [self.player seekToTime:self.playerItem.playerTime completionHandler:^(BOOL finished) {
          if (finished && !holdPlayback) {
            NSLog(@"Current item is ready and will start playing; seeked to %f", CMTimeGetSeconds(self.playerItem.playerTime));
            self.player.rate = self.rateForPlayback;
          } else {
            NSLog(@"Current item is ready, but playback is being help or the initial seek failed");
          }
        }];
      } else if (!holdPlayback) {
        NSLog(@"Current item is ready and will start playing from current player time");
        self.player.rate = self.rateForPlayback;
      } else {
        NSLog(@"Current item is ready, but playback is being held");
      }
      
    }];
  }
}

#pragma mark - Notifications

- (void)postGeneralChangeNotification {
  [NSNotificationCenter.defaultCenter postNotificationName:PRXPlayerChangeNotification object:self];
}

#pragma mark Keep Alive

- (void)keepAliveInBackground {
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [self beginBackgroundKeepAlive];
    for (int i = 0; i < 24; i++)  {
      //      NSLog(@"keeping alive %d", i * 10);
      [NSThread sleepForTimeInterval:10];
    }
    [self endBackgroundKeepAlive];
  });
}

- (void)beginBackgroundKeepAlive {
  backgroundKeepAliveTaskID = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
    [self endBackgroundKeepAlive];
  }];
}

- (void)endBackgroundKeepAlive {
  [[UIApplication sharedApplication] endBackgroundTask:backgroundKeepAliveTaskID];
  backgroundKeepAliveTaskID = UIBackgroundTaskInvalid;
}

#pragma mark Audio Session Interruption

- (void)audioSessionInterruption:(NSNotification *)notification {
  NSLog(@"An audioSessionInterruption notification was received");

  id interruptionTypeKey = notification.userInfo[AVAudioSessionInterruptionTypeKey];

  if ([interruptionTypeKey isEqual:@(AVAudioSessionInterruptionTypeBegan)]) {
    [self audioSessionDidBeginInterruption:notification];
  } else if ([interruptionTypeKey isEqual:@(AVAudioSessionInterruptionTypeEnded)]) {
    [self audioSessionDidEndInterruption:notification];
  }
}

- (void)audioSessionDidBeginInterruption:(NSNotification *)notification {
  NSLog(@"Audio session has been interrupted (this does not mean audio playback was interrupted)");
  [self keepAliveInBackground];
  dateAtAudioPlaybackInterruption = NSDate.date;
}

- (void)audioSessionDidEndInterruption:(NSNotification *)notification {
  NSLog(@"Audio session has interruption ended...");

  // Because of various bugs and unpredictable behavior, it is unreliable to
  // try and recover from audio session interrupts.
  //
  // When something is loaded into AVPlayer and the interrupt ends, even without
  // us doing anything, the player item's status will change. We need to make
  // sure our handling of that change is appropriate
  //
  // If AVPlayer changes to consistently report player rate at the time of the
  // interrupt, or it is able to report interrupts when the rate is 0, this
  // could be handled more directly.
  //
  // As it is now, if the player is paused going into the interrupt, we know
  // the hold flag is set, so when the status changes, even though it will
  // go through the play handler, it won't start playback.
  // In cases where the audio was playing at the interrupt, the hold flag
  // simply won't be set, so it will resume in the play handler.

  // Apparently sometimes the status change does not get reported as soon as
  // the intr. ends, so we do need to coerce it in some cases.
  // REAL DUMB.

  if (dateAtAudioPlaybackInterruption && self.playerItem) {
    // TODO might just need to call bar here
    self.playerItem = self.playerItem;
    //    [self bar];
  }

}

#pragma mark Route changes

- (void)audioSessionRouteChange:(NSNotification *)notification {
  NSUInteger reason = [notification.userInfo[AVAudioSessionRouteChangeReasonKey] integerValue];

  //  For reference only
  //  typedef enum : NSUInteger {
  //    AVAudioSessionRouteChangeReasonUnknown = 0,
  //    AVAudioSessionRouteChangeReasonNewDeviceAvailable = 1,
  //    AVAudioSessionRouteChangeReasonOldDeviceUnavailable = 2,
  //    AVAudioSessionRouteChangeReasonCategoryChange = 3,
  //    AVAudioSessionRouteChangeReasonOverride = 4,
  //    AVAudioSessionRouteChangeReasonWakeFromSleep = 6,
  //    AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory = 7,
  //    AVAudioSessionRouteChangeReasonRouteConfigurationChange = 8,
  //  } AVAudioSessionRouteChangeReason;

  NSLog(@"Audio session route changed: %lu", (unsigned long)reason);
  //  AVAudioSessionRouteDescription* previousRoute = notification.userInfo[AVAudioSessionRouteChangePreviousRouteKey];
  //  AVAudioSessionRouteDescription* currentRoute = [AVAudioSession.sharedInstance currentRoute];

  switch (reason) {
    case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
      [self pause];
      break;
    default:
      break;
  }
}

@end
