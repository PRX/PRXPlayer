//
//  PRXPlayerQueue.h
//  PRXPlayer
//
//  Created by Rebecca Nesson on 2/19/13.
//  Copyright (c) 2013 PRX. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol PRXPlayerQueueDelegate;

@interface PRXPlayerQueue : NSMutableArray

@property (nonatomic, weak) id<PRXPlayerQueueDelegate> delegate;
@property (nonatomic) NSUInteger cursor;

@property (nonatomic, readonly) BOOL isEmpty;

@end

@protocol PRXPlayerQueueDelegate <NSObject>

- (void) queueDidChange:(PRXPlayerQueue *)queue;

@end
