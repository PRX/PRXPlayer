//
//  PRXAudioPlayer.h
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

#import "PRXPlayer.h"
#import "PRXPlayerQueue.h"

@interface PRXQueuePlayer : PRXPlayer <PRXPlayerQueueDelegate>

@property (strong, nonatomic, readonly) PRXPlayerQueue *queue;

@property (nonatomic, readonly) BOOL hasNext;
@property (nonatomic, readonly) BOOL hasPrevious;

@property (nonatomic, readonly) NSUInteger previousPosition;
@property (nonatomic, readonly) NSUInteger nextPosition;

- (BOOL)canMoveToQueuePosition:(NSUInteger)position;
- (void)moveToQueuePosition:(NSUInteger)position;
- (void)seekToQueuePosition:(NSUInteger)position;

- (void)seekForward;
- (void)seekBackward;

- (void)enqueue:(id<PRXPlayerItem>)playerItem;
- (void)enqueue:(id<PRXPlayerItem>)playerItem atPosition:(NSUInteger)position;
- (void)enqueueAfterCurrentPosition:(id<PRXPlayerItem>)playerItem;

- (void)dequeue:(id<PRXPlayerItem>)playerItem;
- (void)dequeueFromPosition:(NSUInteger)position;
- (void)requeue:(id<PRXPlayerItem>)playerItem atPosition:(NSUInteger)position;
- (void)movePlayerItemFromPosition:(NSUInteger)inPosition toPosition:(NSUInteger)outPosition;

- (void)enqueuePlayerItems:(NSArray *)playerItems;
- (void)enqueuePlayerItems:(NSArray *)playerItems atPosition:(NSUInteger)position;

- (void)emptyQueue;

- (BOOL)queueContainsPlayerItem:(id<PRXPlayerItem>)playerItem;
- (NSUInteger)firstQueuePositionForPlayerItem:(id<PRXPlayerItem>)playerItem;
- (NSUInteger)nextQueuePositionForPlayerItem:(id<PRXPlayerItem>)playerItem;
- (NSIndexSet *)allQueuePositionsForPlayerItem:(id<PRXPlayerItem>)playerItem;
- (id<PRXPlayerItem>)playerItemAtCurrentQueuePosition;
- (id<PRXPlayerItem>)playerItemAtQueuePosition:(NSUInteger)position;

@end
