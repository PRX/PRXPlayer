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

#import "PRXPlayer_private.h"
#import "PRXQueuePlayer.h"

@implementation PRXQueuePlayer

- (id)init {
  self = [super init];
  if (self) {
    _queue = [[PRXPlayerQueue alloc] init];
    self.queue.delegate = self;
  }
  return self;
}

- (void)setPlayerItem:(id<PRXPlayerItem>)playerItem {
  if ([self queueContainsPlayerItem:playerItem]) {
    self.queue.position = [self nextQueuePositionForPlayerItem:playerItem];
    super.playerItem = playerItem;
  } else {
    if (playerItem) {
      [self enqueueAfterCurrentPosition:playerItem];
    }
    
    if ([self queueContainsPlayerItem:playerItem]) {
      super.playerItem = playerItem;
    }
  }
}

- (void)play {
  if (self.queue.isEmpty) {
    [super play];
  } else {
    if (self.queue.position == NSNotFound) {
      [self moveToQueuePosition:0];
    }
    [self playPlayerItem:self.queue[self.queue.position]];
  }
}

- (void)playerItemStatusDidChange:(NSDictionary *)change {
  NSUInteger keyValueChangeKind = [change[NSKeyValueChangeKindKey] integerValue];
  
  if (keyValueChangeKind == NSKeyValueChangeSetting && self.player.currentItem.status == AVPlayerStatusFailed) {
    //    PRXLog(@"Player status failed %@", self.player.currentItem.error);
    // the AVPlayer has trouble switching from stream to file and vice versa
    // if we get an error condition, start over playing the thing it tried to play.
    // Once a player fails it can't be used for playback anymore!
    
    NSUInteger _retryLimit = 3;
    
    if ([self.delegate respondsToSelector:@selector(retryLimitForPlayer:)]) {
      _retryLimit = [self.delegate retryLimitForPlayer:self];
    }
    
    if (retryCount < _retryLimit) {
      [super mediaPlayerCurrentItemStatusDidChange:change];
    } else {
      [self postGeneralChangeNotification];
      [self seekForward];
    }
  } else {
    [super mediaPlayerCurrentItemStatusDidChange:change];
  }
}

#pragma mark - Next and previous

- (BOOL)hasPrevious {
  return (self.queue.position != NSNotFound && self.queue.position > 0 && self.queue.count > 1);
}

- (BOOL)hasNext {
  return (self.queue.position != NSNotFound && self.queue.position < (self.queue.count - 1));
}

- (NSUInteger)previousPosition {
  return self.hasPrevious ? (self.queue.position - 1) : NSNotFound;
}

- (NSUInteger)nextPosition {
  return self.hasNext ? (self.queue.position + 1) : NSNotFound;
}

#pragma mark - Queue movement

- (BOOL)canMoveToQueuePosition:(NSUInteger)position {
  if (self.queue.count == 0) { return NO; }
  
  return (position <= (self.queue.count - 1));
}

- (void)moveToQueuePosition:(NSUInteger)position {
  if ([self canMoveToQueuePosition:position]) {
    self.queue.position = position;
  }
}

- (void)seekToQueuePosition:(NSUInteger)position {
  if ([self canMoveToQueuePosition:position]) {
    [self moveToQueuePosition:position];
    self.playerItem = self.queue[self.queue.position];
  }
}

- (void)seekForward {
  if (self.hasNext) {
    [self seekToQueuePosition:self.nextPosition];
  }
}

- (void)seekBackward {
  if (self.hasPrevious) {
    [self seekToQueuePosition:self.previousPosition];
  }
}

- (void)moveToPrevious {
  if (self.hasPrevious) {
    [self moveToQueuePosition:self.previousPosition];
  }
}

- (void)moveToNext {
  if (self.hasNext) {
    [self moveToQueuePosition:self.nextPosition];
  }
}

#pragma mark - Queue manipulation

- (void)enqueue:(id<PRXPlayerItem>)playerItem atPosition:(NSUInteger)position {
  [self.queue insertObject:playerItem atIndex:position];
  
  if (!self.playerItem) {
    if (self.queue.position == NSNotFound) {
      self.queue.position = 0;
    }
    
    [self loadPlayerItem:self.queue[self.queue.position]];
  }
}

- (void)enqueue:(id<PRXPlayerItem>)playerItem {
  [self enqueue:playerItem atPosition:self.queue.count];
}

- (void)enqueueAfterCurrentPosition:(id<PRXPlayerItem>)playerItem {
  NSUInteger position = (self.queue.count == 0 ? 0 : (self.queue.position + 1));
  [self enqueue:playerItem atPosition:position];
}

- (void)dequeueFromPosition:(NSUInteger)position {
  [self.queue removeObjectAtIndex:position];
}

- (void)dequeue:(id<PRXPlayerItem>)playerItem {
  NSUInteger position = [self firstQueuePositionForPlayerItem:playerItem];
  if (position != NSNotFound) {
    [self dequeueFromPosition:position];
  }
}

- (void)movePlayerItemFromPosition:(NSUInteger)position toPosition:(NSUInteger)newPosition {
  if ([self canMoveToQueuePosition:position] && [self canMoveToQueuePosition:newPosition]) {
    // If the current item is being moved, we
    // want to make sure the position in the queue
    // follows it.
    BOOL moveQueuePositionToNewPosition = (position == self.queue.position);
    
    id<PRXPlayerItem> playerItem = self.queue[position];
    
    [self.queue removeObjectAtIndex:position];
    [self.queue insertObject:playerItem atIndex:newPosition];
    
    if (moveQueuePositionToNewPosition) {
      self.queue.position = newPosition;
    }
  }
}

- (void)requeue:(id<PRXPlayerItem>)playerItem atPosition:(NSUInteger)position {
  NSUInteger index = [self firstQueuePositionForPlayerItem:playerItem];
  if (index != NSNotFound) {
    [self movePlayerItemFromPosition:index toPosition:position];
  }
}

- (void)enqueuePlayerItems:(NSArray *)playerItems atPosition:(NSUInteger)position {
  NSUInteger iPosition = position;
  
  for (id<PRXPlayerItem> playerItem in playerItems) {
    [self enqueue:playerItem atPosition:iPosition];
    iPosition++;
  }
}

- (void)enqueuePlayerItems:(NSArray *)playerItems {
  [self enqueuePlayerItems:playerItems atPosition:self.queue.count];
}

- (void)emptyQueue {
  @synchronized(self.queue) {
    [self.queue removeAllObjects];
    
    if (self.player.rate != 0.0f) {
      [self enqueue:self.playerItem];
      [self postGeneralChangeNotification];
    }
  }
}

#pragma mark - Queue queries

- (BOOL)queueContainsPlayerItem:(id<PRXPlayerItem>)playerItem {
  return ([self firstQueuePositionForPlayerItem:playerItem] != NSNotFound);
}

- (id<PRXPlayerItem>)playerItemAtQueuePosition:(NSUInteger)position {
  return [self.queue objectAtIndex:position];
}

- (id)playerItemAtCurrentQueuePosition {
  return [self.queue objectAtIndex:self.queue.position];
}

- (NSUInteger)firstQueuePositionForPlayerItem:(id<PRXPlayerItem>)playerItem {
  @synchronized(self.queue) {
    return [self.queue indexOfObjectPassingTest:^BOOL(id<PRXPlayerItem> aPlayerItem, NSUInteger idx, BOOL *stop) {
      return [aPlayerItem isEqualToPlayerItem:playerItem];
    }];
  }
}

- (NSUInteger)nextQueuePositionForPlayerItem:(id<PRXPlayerItem>)playerItem {
  @synchronized(self.queue) {
    NSUInteger position;
    
    position = [self.queue indexOfObjectPassingTest:^BOOL(id<PRXPlayerItem> aPlayerItem, NSUInteger idx, BOOL* stop) {
      return ([aPlayerItem isEqualToPlayerItem:playerItem] && idx >= self.queue.position);
    }];
    
    if (position == NSNotFound) {
      position = [self firstQueuePositionForPlayerItem:playerItem];
    }
    
    return position;
  }
}

- (NSIndexSet *)allQueuePositionsForPlayerItem:(id<PRXPlayerItem>)playerItem {
  return [self.queue indexesOfObjectsPassingTest:^BOOL(id<PRXPlayerItem>aPlayerItem, NSUInteger idx, BOOL *stop) {
    return [aPlayerItem isEqualToPlayerItem:playerItem];
  }];
}

#pragma mark - Remote control

- (void)remoteControlReceivedWithEvent:(UIEvent *)event {
  [super remoteControlReceivedWithEvent:event];
  
  switch (event.subtype) {
    case UIEventSubtypeRemoteControlNextTrack:
      [self seekForward];
      break;
		case UIEventSubtypeRemoteControlPreviousTrack:
      [self seekBackward];
			break;
		default:
			break;
	}
}

- (NSDictionary *)MPNowPlayingInfoCenterNowPlayingInfo {
  NSMutableDictionary *info = super.MPNowPlayingInfoCenterNowPlayingInfo.mutableCopy;
  
  if (!info[MPMediaItemPropertyAlbumTrackNumber]) {
    NSUInteger position = (self.queue.position == NSNotFound ? 0 : self.queue.position);
    NSUInteger count = (position + 1);
    
    info[MPMediaItemPropertyAlbumTrackNumber] = @(count);
  }
  
  if (!info[MPMediaItemPropertyAlbumTrackCount]) {
    info[MPMediaItemPropertyAlbumTrackCount] = @(self.queue.count);
  }
  
  return info;
}

#pragma mark - PRXAudioQueue delegate

- (void)queueDidChange:(PRXPlayerQueue*)queue {
  [self postGeneralChangeNotification];
}

#pragma mark -- Overrides

- (void)playerItemDidPlayToEndTime:(NSNotification *)notification {
  [super mediaPlayerCurrentItemDidPlayToEndTime:notification];
  [self seekForward];
}

@end
