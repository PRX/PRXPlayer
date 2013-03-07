//
//  PRXAudioPlayer.m
//  PRXPlayer
//
//  Copyright (c) 2013 PRX.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "PRXQueuePlayer.h"
#import "PRXPlayer_private.h"

@implementation PRXQueuePlayer

- (id)init {
    self = [super init];
    if (self) {
        _queue = [[PRXPlayerQueue alloc] init];
        self.queue.delegate = self;
    }
    return self;
}

- (void) loadAndPlayPlayable:(id<PRXPlayable>)playable {
    if ([self queueContainsPlayable:playable]) {
        PRXLog(@"Queue contains playable, passing along.");
        self.queue.cursor = [self nextQueuePositionForObject:playable];
        [super loadAndPlayPlayable:playable];
    } else {
        PRXLog(@"Adding episode to queue and playing (or holding).");
        [self enqueueAfterCurrentPosition:playable];
        [self loadAndPlayPlayable:playable];
    }
}

- (void) play {
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

- (void) playQueuePosition:(NSUInteger)position {
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
    int position = (self.queue.count == 0 ? 0 : (self.queue.cursor + 1));
    [self.queue insertObject:playable atIndex:position];
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
        NSNumber* cursor;
        
        if (inPosition == self.queue.cursor) {
            cursor = @(outPosition);
        }
      
        id<PRXPlayable> pl = [self.queue objectAtIndex:inPosition];
        [self.queue removeObjectAtIndex:inPosition];
        [self.queue insertObject:pl atIndex:outPosition];
        
        if (cursor) {
            self.queue.cursor = cursor.integerValue;
        }
    }
}

- (void) enqueuePlayables:(NSArray *)playables {
    for (id<PRXPlayable> playable in playables) {
        [self enqueue:playable];
    }
}

- (void) emptyQueue {
    [self.queue removeAllObjects];
  
    if (self.player.rate > 0.0f) {
        [self enqueue:self.currentPlayable];
        [self reportPlayerStatusChangeToObservers];
    }
}

- (BOOL) queueContainsPlayable:(id<PRXPlayable>)playable {
    if (self.queue.count == 0) { return NO; }
    
    NSUInteger _idx = [self.queue indexOfObjectPassingTest:^BOOL(id<PRXPlayable>pl, NSUInteger idx, BOOL *stop) {
        return [pl isEqualToPlayable:playable];
    }];
    
    return _idx != NSNotFound;
}

- (int) firstQueuePositionForObject:(id<PRXPlayable>)playable {
    return [self.queue indexOfObjectPassingTest:^BOOL(id<PRXPlayable> pl, NSUInteger idx, BOOL *stop) {
        return [pl isEqualToPlayable:playable];
    }]; 
}

- (int) nextQueuePositionForObject:(id<PRXPlayable>)playable {
    NSUInteger _idx;
    
    _idx = [self.queue indexOfObjectPassingTest:^BOOL(id<PRXPlayable> pl, NSUInteger idx, BOOL *stop) {
        return ([pl isEqualToPlayable:playable] && idx >= self.queue.cursor);
    }];
    
    if (_idx == NSNotFound) {
        _idx = [self firstQueuePositionForObject:playable];
    }
    
    return _idx;
}

- (NSIndexSet *) allQueuePositionsForObject:(id<PRXPlayable>)playable {
    return [self.queue indexesOfObjectsPassingTest:^BOOL(id<PRXPlayable>pl, NSUInteger idx, BOOL *stop) {
        return [pl isEqualToPlayable:playable];
    }];
}

- (id<PRXPlayable>) playableAtCurrentQueuePosition {
    return [self.queue objectAtIndex:self.queue.cursor];
}

- (id<PRXPlayable>) playableAtQueuePosition:(NSUInteger)position {
    return [self.queue objectAtIndex:position]; 
}

- (NSDictionary*) MPNowPlayingInfoCenterNowPlayingInfo {
    NSMutableDictionary *info;
    
    info = [[super MPNowPlayingInfoCenterNowPlayingInfo] mutableCopy];
    
    if (!info[MPMediaItemPropertyAlbumTrackCount]) {
        info[MPMediaItemPropertyAlbumTrackCount] = @(self.queue.count);
    }

    if (!info[MPMediaItemPropertyAlbumTrackNumber]) {
        info[MPMediaItemPropertyAlbumTrackNumber] = @(self.queue.cursor + 1);
    }
    
    return info;
}

#pragma mark - PRXAudioQueue delegate

- (void) queueDidChange:(PRXPlayerQueue *)queue {
    [self reportPlayerStatusChangeToObservers]; 
}

@end
