//
//  TSTViewController.h
//  NewPlayerTest
//
//  Created by Christopher Kalafarski on 9/17/13.
//  Copyright (c) 2013 Bitnock. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "PRXPlayer.h"

@interface TSTViewController : UIViewController <PRXPlayerDelegate>

@property (nonatomic, strong) IBOutlet UILabel *playerStatusLabel;
@property (nonatomic, strong) IBOutlet UILabel *assetLabel;
@property (nonatomic, strong) IBOutlet UILabel *reachLabel;

@property (nonatomic, strong) IBOutlet UIButton *playbackRateButton;

@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *activityIndicatorView;
@property (nonatomic, strong) IBOutlet UISwitch *interruptIndicatorSwitch;

- (IBAction)playButtonAction:(id)sender;
- (IBAction)pauseButtonAction:(id)sender;
- (IBAction)toggleButtonAction:(id)sender;
- (IBAction)stopButtonAction:(id)sender;

- (IBAction)jumpForwardButtonAction:(id)sender;

- (IBAction)playbackRateButtonAction:(id)sender;

- (IBAction)loadItemButtonAction:(id)sender;
- (IBAction)playItemButtonAction:(id)sender;

- (IBAction)playPlaylistItemButtonAction:(id)sender;

- (IBAction)loadItem2ButtonAction:(id)sender;
- (IBAction)playItem2ButtonAction:(id)sender;

- (IBAction)playItemHybridButtonAction:(id)sender;

- (IBAction)loadItemFailureButtonAction:(id)sender;
- (IBAction)loadTracksFailureButtonAction:(id)sender;

@end
