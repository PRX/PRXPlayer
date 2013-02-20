//
//  PRXQueueAudioPlayer.m
//  PRXNewAudioPlayerTester
//
//  Created by Rebecca Nesson on 2/19/13.
//  Copyright (c) 2013 PRX. All rights reserved.
//

#import "PRXQueueAudioPlayer.h"
#import "PRXAudioPlayer_private.h"

@implementation PRXQueueAudioPlayer

- (BOOL) hasNext;
{
- (void)loadAndPlayPlayable:(id<PRXPlayable>)playable {
  if ([self queueContainsPlayable:playable]) {
    self.queue.cursor = [self nextQueuePositionForObject:playable];
    [super loadAndPlayPlayable:playable];
  } else {
    PRXLog(@"Adding episode to queue and playing (or holding).");
    [self enqueueAfterCurrentPosition:playable];
  }
}

- (void)play {
  if (self.currentPlayable) {
    [super play];
  } else if (self.queue.isEmpty) {
    [self loadAndPlayPlayable:self.queue[self.queue.cursor]];
  }
}

- (BOOL) hasNext {
    return (self.queue.cursor != NSNotFound && self.queue.cursor < [self.queue count] - 1);
}

- (BOOL) hasPrevious { 
    return self.queue.cursor > 0;
}

- (BOOL) hasQueuePosition:(NSUInteger)position {
    return (position < [self.queue count] - 1);
}

- (void) moveToNext {
    if (self.hasNext) {
        [self.queue setCursor:self.queue.cursor + 1];
    }
}

- (void) moveToPrevious {
    if (self.hasPrevious) {
        [self.queue setCursor:self.queue.cursor - 1];
    }
}

- (void) moveToQueuePosition:(NSUInteger)position {
    if ([self hasQueuePosition:position]) {
        [self.queue setCursor:position];
    }
}

- (void) playNext {
    if (self.hasNext) { 
        [self moveToNext];
        [self loadAndPlayPlayable:self.queue[self.queue.cursor]];
    }
}

- (void) playPrevious {
    if (self.hasPrevious) {
        [self moveToPrevious];
        [self loadAndPlayPlayable:self.queue[self.queue.cursor]];
    }
}

- (void) playQueuePosition:(NSUInteger)position
{
    if ([self hasQueuePosition:position]) {
        [self moveToQueuePosition:position];
        [self loadAndPlayPlayable:self.queue[self.queue.cursor]];
    }
}

- (void) enqueue:(id<PRXPlayable>)playable {
    [self.queue addObject:playable]; 
}

- (void) enqueue:(id<PRXPlayable>)playable atPosition:(NSUInteger)position {
    [self.queue insertObject:playable atIndex:position];
}

- (void) enqueueAfterCurrentPosition:(id<PRXPlayable>)playable {
    [self.queue insertObject:playable atIndex:self.queue.cursor + 1];
}

- (void) dequeue:(id<PRXPlayable>)playable {
    int index = [self firstQueuePositionForObject:playable];
    if (index != NSNotFound) {
        [self.queue removeObjectAtIndex:index];
    }
}

- (void) dequeueFromPosition:(NSUInteger)position {
    [self.queue removeObjectAtIndex:position]; 
}

- (void) requeue:(id<PRXPlayable>)playable atPosition:(NSUInteger)position {
    int index = [self firstQueuePositionForObject:playable];
    if (index != NSNotFound) {
        [self movePlayableFromPosition:index toPosition:position];
    }
}

- (void) movePlayableFromPosition:(NSUInteger)inPosition toPosition:(NSUInteger)outPosition {
    if ([self hasQueuePosition:inPosition] && [self hasQueuePosition:outPosition]) {
        id<PRXPlayable> pl = [self.queue objectAtIndex:inPosition];
        [self.queue removeObjectAtIndex:inPosition];
        [self.queue insertObject:pl atIndex:outPosition];
    }
}

- (void) enqueuePlayables:(NSArray *)playables {
    for (id<PRXPlayable> playable in playables) {
        [self enqueue:playable];
    }
}

- (void) emptyQueue {
    [self.queue removeAllObjects];
}

- (BOOL) queueContainsPlayable:(id<PRXPlayable>)playable {
    return [self.queue indexOfObjectPassingTest:^BOOL(id<PRXPlayable>pl, NSUInteger idx, BOOL *stop) {
        return [pl isEqualToPlayable:playable];
    }] != NSNotFound; 
}

- (int) firstQueuePositionForObject:(id<PRXPlayable>)playable {
    return [self.queue indexOfObjectPassingTest:^BOOL(id<PRXPlayable> pl, NSUInteger idx, BOOL *stop) {
        return [pl isEqualToPlayable:playable];
    }]; 
}

- (int) nextQueuePositionForObject:(id<PRXPlayable>)playable {
    return [self.queue indexOfObjectPassingTest:^BOOL(id<PRXPlayable> pl, NSUInteger idx, BOOL *stop) {
        return ([pl isEqualToPlayable:pl] && idx >= self.queue.cursor);
    }];
}

- (NSIndexSet *) allQueuePositionsForObject:(id<PRXPlayable>)playable {
    return [self.queue indexesOfObjectsPassingTest:^BOOL(id<PRXPlayable>playable, NSUInteger idx, BOOL *stop) {
        return [playable isEqualToPlayable:playable];
    }];
}

- (id<PRXPlayable>)playableAtCurrentQueuePosition {
    return [self.queue objectAtIndex:self.queue.cursor];
}

- (id<PRXPlayable>)playableAtQueuePosition:(NSUInteger)position {
    return [self.queue objectAtIndex:position]; 
}

#pragma mark - PRXAudioQueue delegate

- (void) queueDidChange:(PRXAudioQueue *)queue {
    [self reportPlayerStatusChangeToObservers]; 
}

@end
