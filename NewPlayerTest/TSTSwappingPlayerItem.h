//
//  TSTSwappingPlayerItem.h
//  NewPlayerTest
//
//  Created by Christopher Kalafarski on 9/19/13.
//  Copyright (c) 2013 Bitnock. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PRXPlayer.h"

@interface TSTSwappingPlayerItem : NSObject <PRXPlayerItem>

@property (nonatomic, strong) NSURL *remoteURL;
@property (nonatomic, strong) NSURL *localURL;

- (void)swap;

@end
