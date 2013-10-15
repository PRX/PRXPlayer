//
//  TSTPlayerItem.h
//  NewPlayerTest
//
//  Created by Christopher Kalafarski on 9/18/13.
//  Copyright (c) 2013 Bitnock. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PRXPlayer.h"

@interface TSTPlayerItem : NSObject <PRXPlayerItem>

- (id)initWithURL:(NSURL *)URL;

@end
