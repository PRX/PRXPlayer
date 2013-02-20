//
//  APViewController.h
//  PRXNewAudioPlayerTester
//
//  Created by Rebecca Nesson on 2/19/13.
//  Copyright (c) 2013 PRX. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "APEpisode.h"

#import "PRXAudioPlayer.h"

@interface APViewController : UIViewController <PRXAudioPlayerObserver>

@property (nonatomic, strong) IBOutlet UILabel* queueLabel;
@property (nonatomic, strong) IBOutlet UILabel* timeLabel;
@property (nonatomic, strong) IBOutlet UILabel* stateLabel;

- (IBAction)playRemixStreamPressed:(id)sender;
- (IBAction)playWBURStream:(id)sender; 

- (IBAction)play99PercentPressed:(id)sender;
- (IBAction)playMothPressed:(id)sender;

@end
