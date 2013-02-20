//
//  PRXAudioQueue.h
//  PRXNewAudioPlayerTester
//
//  Created by Rebecca Nesson on 2/19/13.
//  Copyright (c) 2013 PRX. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol PRXAudioQueueDelegate; 

@interface PRXAudioQueue : NSMutableArray

@property (nonatomic, weak) id<PRXAudioQueueDelegate> delegate;
@property (nonatomic) NSUInteger cursor;

@property (nonatomic, readonly) BOOL isEmpty;

@end

@protocol PRXAudioQueueDelegate <NSObject>

- (void) queueDidChange:(PRXAudioQueue *)queue; 

@end
