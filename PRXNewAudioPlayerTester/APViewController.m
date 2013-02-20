//
//  APViewController.m
//  PRXNewAudioPlayerTester
//
//  Created by Rebecca Nesson on 2/19/13.
//  Copyright (c) 2013 PRX. All rights reserved.
//

#import "APViewController.h"
#import "PRXAudioPlayer.h"
#import "PRXQueueAudioPlayer.h"

@interface APViewController ()

@property (nonatomic, strong) APEpisode *remixStream;
@property (nonatomic, strong) APEpisode *wburStream;
@property (nonatomic, strong) APEpisode *ninetyNine;
@property (nonatomic, strong) APEpisode *moth;

@end

@implementation APViewController

- (void) observedPlayerStatusDidChange:(AVPlayer *)player {
    [self labelize];    
}


- (void) observedPlayerDidObservePeriodicTimeInterval:(AVPlayer *)player {
    [self labelize];
}

- (void)labelize {
    PRXQueueAudioPlayer* pl = PRXQueueAudioPlayer.sharedPlayer;
    
    self.queueLabel.text = [NSString stringWithFormat:@"%i of %i", (pl.queue.cursor + 1), pl.queue.count];
    
    float sec = (pl.player.currentItem.currentTime.value / pl.player.currentItem.currentTime.timescale);

    self.timeLabel.text = [NSString stringWithFormat:@"%f : %f", sec, CMTimeGetSeconds(pl.player.currentItem.duration)];
    self.stateLabel.text = [NSString stringWithFormat:@"IDK!!"];
    
    [self.timeLabel setNeedsDisplay];
}


- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    [PRXQueueAudioPlayer.sharedPlayer addObserver:self persistent:YES];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) playRemixStreamPressed:(id)sender;
{
    if (!self.remixStream) { self.remixStream = [[APEpisode alloc] initWithIdentifier:0]; }
    [[PRXQueueAudioPlayer sharedPlayer] playPlayable:self.remixStream];
}

- (void) play99PercentPressed:(id)sender;
{
    if (!self.ninetyNine) { self.ninetyNine = [[APEpisode alloc] initWithIdentifier:1]; }
    [[PRXQueueAudioPlayer sharedPlayer] playPlayable:self.ninetyNine];
}

- (void) playWBURStream:(id)sender; 
{
    if (!self.wburStream) { self.wburStream = [[APEpisode alloc] initWithIdentifier:2]; }
    [[PRXQueueAudioPlayer sharedPlayer] playPlayable:self.wburStream];
}

- (IBAction)playMothPressed:(id)sender {
    if (!self.moth) { self.moth = [[APEpisode alloc] initWithIdentifier:3]; }
    [[PRXQueueAudioPlayer sharedPlayer] playPlayable:self.moth];

}

@end
