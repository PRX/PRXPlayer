//
//  TSTViewController.m
//  NewPlayerTest
//
//  Created by Christopher Kalafarski on 9/17/13.
//  Copyright (c) 2013 Bitnock. All rights reserved.
//

@import AVFoundation;

#import "TSTViewController.h"
#import "TSTPlayerItem.h"
#import "TSTSwappingPlayerItem.h"
#import "Reachability.h"

@interface TSTViewController () {
  NSTimer *uiTimer;
  TSTSwappingPlayerItem *swapItem;
  
  float playbackRate;
}

@property (nonatomic, strong, readonly) Reachability *reach;

@end

@implementation TSTViewController

// delegate

- (float)filePlaybackRateForPlayer:(PRXPlayer *)player {
  NSLog(@">>>>> [Delegate] File playback rate: %f", playbackRate);
  return playbackRate;
}

- (BOOL)playerAllowsPlaybackViaWWAN:(PRXPlayer *)player {
  return YES;
}

//

- (void)viewDidLoad {
  [super viewDidLoad];
  
  _reach = [Reachability reachabilityWithHostname:@"www.google.com"];
  [self.reach startNotifier];

  PRXPlayer.sharedPlayer.delegate = self;
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(observedPlayerDidObservePeriodicTimeInterval:)
                                               name:PRXPlayerTimeIntervalNotification
                                             object:PRXPlayer.sharedPlayer];
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(observedPlayerDidObserveLongPeriodicTimeInterval:)
                                               name:PRXPlayerLongTimeIntervalNotification
                                             object:PRXPlayer.sharedPlayer];
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(observedPlayerDidChange:)
                                               name:PRXPlayerChangeNotification
                                             object:PRXPlayer.sharedPlayer];

  
  playbackRate = 1.0f;
  
  NSError *setCategoryError = nil;
  BOOL success = [[AVAudioSession sharedInstance]
                  setCategory: AVAudioSessionCategoryPlayback
                  error: &setCategoryError];
  
  if (!success) { /* handle the error in setCategoryError */ }
  NSError *activationError = nil;
  success = [[AVAudioSession sharedInstance] setActive:YES error: &activationError];
  if (!success) { /* handle the error in activationError */ }
  
  uiTimer = [NSTimer scheduledTimerWithTimeInterval:0.2f target:self selector:@selector(updateUI) userInfo:nil repeats:YES];
}

//notifications from player

- (void)observedPlayerDidChange:(NSNotification *)notification {
//  NSLog(@"[NOTIFICATION] Player Change");
}

- (void)observedPlayerDidObservePeriodicTimeInterval:(NSNotification *)notification {
//  NSValue *time_v = notification.userInfo[@"time"];
//  CMTime time = time_v.CMTimeValue;
//  
//  NSLog(@"[NOTIFICATION] Time interval: %f", CMTimeGetSeconds(time));
}

- (void)observedPlayerDidObserveLongPeriodicTimeInterval:(NSNotification *)notification {
//  NSValue *time_v = notification.userInfo[@"time"];
//  CMTime time = time_v.CMTimeValue;
//  
//  NSLog(@"[NOTIFICATION] Long time interval: %f", CMTimeGetSeconds(time));
}

- (void)updateUI {
  
  AVPlayerItemAccessLog* accessLog = PRXPlayer.sharedPlayer.player.currentItem.accessLog;
  if (accessLog) {
    NSArray *events = accessLog.events;
    
    if (events.count > 0) {
      AVPlayerItemAccessLogEvent *event = (AVPlayerItemAccessLogEvent *)events.lastObject;
      
      NSLog(@"URI: %@", event.URI);
      NSLog(@"Type: %@", event.playbackType);
    }
  }

  
  
  NSTimeInterval buffer = [[PRXPlayer sharedPlayer] buffer];
  
  NSString *state;
  
  switch (PRXPlayer.sharedPlayer.state) {
    case PRXPlayerStateUnknown:
      state = @"??? Unknown";
      break;
    case PRXPlayerStateEmpty:
      state = @"Empty";
      break;
    case PRXPlayerStateLoading:
      state = @"Loading";
      break;
    case PRXPlayerStateReady:
      state = @"Ready";
      break;
    case PRXPlayerStateWaiting:
      state = @"Waiting";
      break;
    case PRXPlayerStateBuffering:
      state = @"Buffering";
      break;
    default:
      state = @"n/a";
      break;
  }
  
  if (PRXPlayer.sharedPlayer.state == PRXPlayerStateBuffering
      || PRXPlayer.sharedPlayer.state == PRXPlayerStateLoading) {
    if (!self.activityIndicatorView.isAnimating) {
      [self.activityIndicatorView startAnimating];
    }
  } else {
    [self.activityIndicatorView stopAnimating];
  }
  
  if (PRXPlayer.sharedPlayer.dateAtAudioPlaybackInterruption) {
    [self.interruptIndicatorSwitch setOn:YES];
  } else {
    [self.interruptIndicatorSwitch setOn:NO];
  }
  
  BOOL local = NO;
  
  if ([PRXPlayer.sharedPlayer.player.currentItem.asset isKindOfClass:AVURLAsset.class]) {
    AVURLAsset *asset = (AVURLAsset *)PRXPlayer.sharedPlayer.player.currentItem.asset;
    if ([asset.URL isFileURL]) {
      local = YES;
    }
  }
  
  self.playerStatusLabel.text = [NSString stringWithFormat:@"Buffer(%f) PRXPlayerState(%@) PlayerStatus(%li) CurrentItemStatus(%li) Rate(%f) Local(%i)", buffer, state, (long)PRXPlayer.sharedPlayer.player.status, (long)PRXPlayer.sharedPlayer.player.currentItem.status, PRXPlayer.sharedPlayer.player.rate, local];
  
  self.assetLabel.text = PRXPlayer.sharedPlayer.player.currentItem.asset.description;
  
  self.reachLabel.text = [NSString stringWithFormat:@"String: %@ - Reachable: %i - WWAN: %i - Wifi: %i - Flags: %@", self.reach.currentReachabilityString, self.reach.isReachable, self.reach.isReachableViaWWAN, self.reach.isReachableViaWiFi, self.reach.currentReachabilityFlags];
}

- (IBAction)playButtonAction:(id)sender {
  [[PRXPlayer sharedPlayer] play];
}

- (IBAction)pauseButtonAction:(id)sender {
  [[PRXPlayer sharedPlayer] pause];
}

- (IBAction)toggleButtonAction:(id)sender {
  [[PRXPlayer sharedPlayer] toggle];
}

- (IBAction)stopButtonAction:(id)sender {
  [[PRXPlayer sharedPlayer] stop];
}

- (IBAction)jumpForwardButtonAction:(id)sender {
  CMTime currentTime = [[[PRXPlayer sharedPlayer] player] currentTime];
  CMTime jump = CMTimeMakeWithSeconds(30, 1000);
  CMTime newTime = CMTimeAdd(currentTime, jump);
  [[[PRXPlayer sharedPlayer] player] seekToTime:newTime];
}

- (IBAction)playbackRateButtonAction:(id)sender {
  if ([self.playbackRateButton.titleLabel.text isEqualToString:@"1x"]) {
    playbackRate = 2.0f;
    [self.playbackRateButton setTitle:@"2x" forState:UIControlStateNormal];
  } else {
    playbackRate = 1.0f;
    [self.playbackRateButton setTitle:@"1x" forState:UIControlStateNormal];
  }
}

- (IBAction)loadItemButtonAction:(id)sender {
  [[PRXPlayer sharedPlayer] loadPlayerItem:TSTPlayerItem.new];
}

- (IBAction)playItemButtonAction:(id)sender {
  [[PRXPlayer sharedPlayer] playPlayerItem:TSTPlayerItem.new];
}

- (IBAction)loadItem2ButtonAction:(id)sender {
//  NSURL *url = [NSURL URLWithString:@"https://dl.dropboxusercontent.com/u/1400235/bogus.m3u"];
  NSURL *url = [NSURL URLWithString:@"http://wbur-sc.streamguys.com/wbur.aac"];
  TSTPlayerItem *playerItem = [[TSTPlayerItem alloc] initWithURL:url];
  
  [[PRXPlayer sharedPlayer] loadPlayerItem:playerItem];
}

- (void)playPlaylistItemButtonAction:(id)sender {
  NSURL *url = [NSURL URLWithString:@"http://www.kqed.org/listen/kqedradio.pls"];
  TSTPlayerItem *playerItem = [[TSTPlayerItem alloc] initWithURL:url];
  
  [[PRXPlayer sharedPlayer] playPlayerItem:playerItem];
}

- (IBAction)playItem2ButtonAction:(id)sender {
//  NSURL *url = [NSURL URLWithString:@"https://dl.dropboxusercontent.com/u/1400235/bogus.m3u"];
  NSURL *url = [NSURL URLWithString:@"http://wbur-sc.streamguys.com/wbur.aac"];
  TSTPlayerItem *playerItem = [[TSTPlayerItem alloc] initWithURL:url];
  
  [[PRXPlayer sharedPlayer] playPlayerItem:playerItem];
}

- (IBAction)playItemHybridButtonAction:(id)sender {
  if (!swapItem) {
    swapItem = [TSTSwappingPlayerItem new];
  }
  
  [swapItem swap];
  
  AVURLAsset *asset = (AVURLAsset *)[swapItem playerAsset];
  NSURL *assetURL = asset.URL;
  
  if ([assetURL isFileURL]) {
    NSLog(@"========== Playing local file from swap item");
  } else {
    NSLog(@"========== Playing swap item with remote file");
  }
  
  [[PRXPlayer sharedPlayer] playPlayerItem:swapItem];
}

- (IBAction)loadItemFailureButtonAction:(id)sender {
  NSURL *url = [NSURL URLWithString:@"https://dl.dropboxusercontent.com/u/1400235/bogus.m3u"];
  TSTPlayerItem *playerItem = [[TSTPlayerItem alloc] initWithURL:url];
  
  [[PRXPlayer sharedPlayer] loadPlayerItem:playerItem];
}

- (IBAction)loadTracksFailureButtonAction:(id)sender {
  NSURL *url = [NSURL URLWithString:@"https://example.com/no-an-mp3.mp3"];
  TSTPlayerItem *playerItem = [[TSTPlayerItem alloc] initWithURL:url];
  
  [[PRXPlayer sharedPlayer] loadPlayerItem:playerItem];
}

@end
