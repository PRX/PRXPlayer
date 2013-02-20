//
//  APViewController.m
//  PRXNewAudioPlayerTester
//
//  Created by Rebecca Nesson on 2/19/13.
//  Copyright (c) 2013 PRX. All rights reserved.
//

#import "APViewController.h"
#import "PRXAudioPlayer.h"

@interface APViewController ()

@property (nonatomic, strong) APEpisode *remixStream;
@property (nonatomic, strong) APEpisode *ninetyNine;
@property (nonatomic, strong) APEpisode *wburStream; 

@end

@implementation APViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void) playRemixStreamPressed:(id)sender;
{
    if (!self.remixStream) { self.remixStream = [[APEpisode alloc] initWithIdentifier:0]; }
    [[PRXAudioPlayer sharedPlayer] playPlayable:self.remixStream];
}

- (void) play99PercentPressed:(id)sender;
{
    if (!self.ninetyNine) { self.ninetyNine = [[APEpisode alloc] initWithIdentifier:1]; }
    [[PRXAudioPlayer sharedPlayer] playPlayable:self.ninetyNine];
}

- (void) playWBURStream:(id)sender; 
{
    if (!self.wburStream) { self.wburStream = [[APEpisode alloc] initWithIdentifier:2]; }
    [[PRXAudioPlayer sharedPlayer] playPlayable:self.wburStream];
}

@end
