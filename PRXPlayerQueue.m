//
//  PRXPlayerQueue.m
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

#import "PRXPlayerQueue.h"

@interface PRXPlayerQueue ()

@property (nonatomic, strong) NSMutableArray *backingStore;

@property (nonatomic) NSUInteger lastCursor;

- (void) incrementCursor;
- (void) decrementCursor;

@end

@implementation PRXPlayerQueue

- (id) init {
    self = [super init];
    if (self) {
        self.backingStore = [NSMutableArray arrayWithCapacity:10];
        self.cursor = NSNotFound;
    }
    return self;
}

- (NSUInteger) lastCursor {
    if (self.count == 0) {
        return NSNotFound;
    } else {
        return (self.count - 1);
    }
}

- (void) setCursor:(NSUInteger)cursor {
    if (cursor == NSNotFound) {
        _cursor = cursor;
    } else if (cursor <= self.lastCursor) {
        _cursor = cursor;
    }
    
    [self notifyDelegate];
}

- (void) incrementCursor {
    if (self.cursor == NSNotFound) {
        self.cursor = 0;
    } else {
        self.cursor = self.cursor + 1;
    }
}

- (void) decrementCursor {
    if (self.cursor == 0) {
        self.cursor = NSNotFound;
    } else {
        self.cursor = self.cursor - 1;
    }
}

- (BOOL) isEmpty {
    return (self.count == 0);
}

- (void) insertObject:(id)anObject atIndex:(NSUInteger)index {
    if (index >= self.backingStore.count) {
        index = self.backingStore.count;
    }
    
    [self.backingStore insertObject:anObject atIndex:index];
    
    if (index <= self.cursor || self.cursor == NSNotFound) {
        [self incrementCursor];
    }
    
    [self notifyDelegate]; 
}

- (void) removeObjectAtIndex:(NSUInteger)index {
    if (index >= self.backingStore.count) { return; }
    
    [self.backingStore removeObjectAtIndex:index];
    
    if (index < self.cursor) {
        [self decrementCursor];
    }
    
    if (self.cursor > self.lastCursor) {
        self.cursor = self.lastCursor;
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

    if (self.cursor > self.lastCursor) {
        self.cursor = self.lastCursor;
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

- (id) objectAtIndex:(NSUInteger)index {
    if (index != NSNotFound && index < self.backingStore.count) {
        return [self.backingStore objectAtIndex:index];
    }
    return nil;
}

- (void) notifyDelegate {
    if (self.delegate && [self.delegate respondsToSelector:@selector(queueDidChange:)]) {
        [self.delegate queueDidChange:self];
    }
}

@end
