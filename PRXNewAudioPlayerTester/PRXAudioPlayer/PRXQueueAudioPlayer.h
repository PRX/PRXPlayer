//
//  PRXQueueAudioPlayer.h
//  PRXNewAudioPlayerTester
//
//  Created by Rebecca Nesson on 2/19/13.
//  Copyright (c) 2013 PRX. All rights reserved.
//

#import "PRXAudioPlayer.h"
#import "PRXAudioQueue.h"

@interface PRXQueueAudioPlayer : PRXAudioPlayer<PRXAudioQueueDelegate>

+ (PRXQueueAudioPlayer *)sharedPlayer;

@property (strong, nonatomic, readonly) PRXAudioQueue *queue;
@property (nonatomic, readonly) BOOL hasNext;
@property (nonatomic, readonly) BOOL hasPrevious;

- (void) moveToNext;
- (void) moveToPrevious;
- (void) playNext;
- (void) playPrevious;
- (void) moveToQueuePosition:(NSUInteger)position;
- (void) playQueuePosition:(NSUInteger)position;
- (BOOL) hasQueuePosition:(NSUInteger)position;

- (void) enqueue:(id<PRXPlayable>)playable; 
- (void) enqueue:(id<PRXPlayable>)playable atPosition:(NSUInteger)position;
- (void) enqueueAfterCurrentPosition:(id<PRXPlayable>)playable;

- (void) dequeue:(id<PRXPlayable>)playable;
- (void) dequeueFromPosition:(NSUInteger)position;
- (void) requeue:(id<PRXPlayable>)playable atPosition:(NSUInteger)position;
- (void) movePlayableFromPosition:(NSUInteger)inPosition toPosition:(NSUInteger)outPosition;

- (void) enqueuePlayables:(NSArray *)playables;

- (void) emptyQueue;

- (BOOL) queueContainsPlayable:(id<PRXPlayable>)playable;
- (int) firstQueuePositionForObject:(id<PRXPlayable>)playable;
- (int) nextQueuePositionForObject:(id<PRXPlayable>)playable;
- (NSIndexSet *) allQueuePositionsForObject:(id<PRXPlayable>)playable;
- (id<PRXPlayable>) playableAtCurrentQueuePosition;
- (id<PRXPlayable>) playableAtQueuePosition:(NSUInteger)position;

@end
