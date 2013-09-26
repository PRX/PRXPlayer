//
//  APViewController.m
//  PRXNewAudioPlayerTester
//
//  Created by Rebecca Nesson on 2/19/13.
//  Copyright (c) 2013 PRX. All rights reserved.
//

#import "APViewController.h"
#import "PRXPlayer.h"
#import "PRXQueuePlayer.h"

@interface APViewController () {
    NSTimer* refreshUITimer;
}

@property (nonatomic, strong) APEpisode *remixStream;
@property (nonatomic, strong) APEpisode *wburStream;
@property (nonatomic, strong) APEpisode *ninetyNine;
@property (nonatomic, strong) APEpisode *moth;

@end

@implementation APViewController

- (void) observedPlayerStatusDidChange:(AVPlayer *)player {
    [self labelize:nil];
}


- (void) observedPlayerDidObservePeriodicTimeInterval:(AVPlayer *)player {
    [self labelize:nil];
}

- (void)labelize:(id)sender {
    PRXQueuePlayer* pl = PRXQueuePlayer.sharedPlayer;
    
    self.queueLabel.text = [NSString stringWithFormat:@"%i of %i", (pl.queue.cursor + 1), pl.queue.count];

    NSLog(@"Rate: %f", pl.player.rate);
    NSLog(@"Seconds; %f", CMTimeGetSeconds(pl.player.currentItem.currentTime));
    NSLog(@"Buffer: %f", pl.buffer);
    NSLog(@"------------------");

    self.timeLabel.text = [NSString stringWithFormat:@"%f : %f", CMTimeGetSeconds(pl.player.currentItem.currentTime), CMTimeGetSeconds(pl.player.currentItem.duration)];
    self.stateLabel.text = [NSString stringWithFormat:@"IDK!!"];
}


- (IBAction)toggleAction:(id)sender {
    [PRXQueuePlayer.sharedPlayer togglePlayPause];
}

- (IBAction)jumpAction:(id)sender {
    CMTime time = CMTimeMake(-3600, 1);
    [[PRXQueuePlayer.sharedPlayer player] seekToTime:time];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    [PRXQueuePlayer.sharedPlayer addObserver:self persistent:YES];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
//    refreshUITimer = [NSTimer scheduledTimerWithTimeInterval:0.4 target:self selector:@selector(labelize:) userInfo:nil repeats:YES];

}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) playRemixStreamPressed:(id)sender;
{
    if (!self.remixStream) { self.remixStream = [[APEpisode alloc] initWithIdentifier:0]; }
    [[PRXQueuePlayer sharedPlayer] playPlayable:self.remixStream];
}

- (void) play99PercentPressed:(id)sender;
{
    if (!self.ninetyNine) { self.ninetyNine = [[APEpisode alloc] initWithIdentifier:1]; }
    [[PRXQueuePlayer sharedPlayer] playPlayable:self.ninetyNine];
}

- (void) playWBURStream:(id)sender; 
{
    if (!self.wburStream) { self.wburStream = [[APEpisode alloc] initWithIdentifier:2]; }
    [[PRXQueuePlayer sharedPlayer] playPlayable:self.wburStream];
}

- (IBAction)playMothPressed:(id)sender {
    if (!self.moth) { self.moth = [[APEpisode alloc] initWithIdentifier:3]; }
    [[PRXQueuePlayer sharedPlayer] playPlayable:self.moth];

}

@end
