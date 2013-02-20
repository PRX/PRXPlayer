//
//  APEpisode.h
//  PRXNewAudioPlayerTester
//
//  Created by Rebecca Nesson on 2/19/13.
//  Copyright (c) 2013 PRX. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PRXAudioPlayer.h"

@interface APEpisode : NSObject<PRXPlayable>

- (id) initWithIdentifier:(int)identifier;

@end
