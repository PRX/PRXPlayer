//
//  PRXAudioQueue.m
//  PRXNewAudioPlayerTester
//
//  Created by Rebecca Nesson on 2/19/13.
//  Copyright (c) 2013 PRX. All rights reserved.
//

#import "PRXAudioQueue.h"
@interface PRXAudioQueue ()

@property (nonatomic, strong) NSMutableArray *backingStore;

@end

@implementation PRXAudioQueue

- (id) init {

    self = [super init];
    if (self) {
        self.backingStore = [NSMutableArray arrayWithCapacity:10];
        self.cursor = NSNotFound;
    }
    return self;
}

- (void) setCursor:(NSUInteger)cursor {
    if (cursor < [self.backingStore count] - 1) {
        _cursor = cursor;
    }
    [self notifyDelegate]; 
}

- (void) insertObject:(id)anObject atIndex:(NSUInteger)index {
    if (index >= [self.backingStore count]) {
        index = [self.backingStore count]; 
    }
    [self.backingStore insertObject:anObject atIndex:index];
    if (index <= self.cursor) {
        self.cursor++;
    }
    [self notifyDelegate]; 
}

- (void) removeObjectAtIndex:(NSUInteger)index {
    if (index >= [self.backingStore count]) { return; }
    [self.backingStore removeObjectAtIndex:index];
    if (index < self.cursor) {
        self.cursor--;
    }
    if (self.cursor > [self.backingStore count] - 1) {
        self.cursor--;
    }
    [self notifyDelegate];
}

- (void) addObject:(id)anObject {
    [self.backingStore addObject:anObject];
    [self notifyDelegate]; 
}

- (void) removeAllObjects {
    [self.backingStore removeAllObjects];
    self.cursor = NSNotFound;
    [self notifyDelegate]; 
}

- (void) removeLastObject {
    [self.backingStore removeLastObject];
    if (self.cursor > [self.backingStore count] - 1) {
        self.cursor--;
    }
    [self notifyDelegate]; 
}

- (void) replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject {
    [self.backingStore replaceObjectAtIndex:index withObject:anObject];
    [self notifyDelegate]; 
}

- (NSUInteger) count {
    return [self.backingStore count]; 
}

- (id)objectAtIndex:(NSUInteger)index {
    if (index != NSNotFound && index < [self.backingStore count]) {
        return [self.backingStore objectAtIndex:index];
    }
    return nil;
}

- (void) notifyDelegate;
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(queueDidChange:)]) {
        [self.delegate queueDidChange:self];
    }
}

@end
