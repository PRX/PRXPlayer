//
//  APEpisode.m
//  PRXNewAudioPlayerTester
//
//  Created by Rebecca Nesson on 2/19/13.
//  Copyright (c) 2013 PRX. All rights reserved.
//

#import "APEpisode.h"

@interface APEpisode ()

@property (nonatomic, readonly) int identifier; 

@end

@implementation APEpisode

- (id) initWithIdentifier:(int)identifier;
{
    self = [super init];
    if (self) {
        _identifier = identifier;
    }
    return self;
}

- (NSURL *)audioURL {
    switch (self.identifier) {
        case 0:
            return [NSURL URLWithString:@"http://stream.publicradioremix.org:8081/remixxm"];
        case 1:
            return [NSURL URLWithString:@"http://www.podtrac.com/pts/redirect.mp3/media.blubrry.com/99percentinvisible/cdn.99percentinvisible.org/wp-content/uploads/73-The-Zanzibar-and-Other-Building-Poems.mp3"];
        case 2:
            return [NSURL URLWithString:@"http://wbur-sc.streamguys.com/wbur.aac"];
        case 3:
            return [NSURL URLWithString:@"http://feeds.themoth.org/~r/themothpodcast/~5/7tiM_vhvFMI/moth-podcast-264-walter-mosley.mp3"];
        default:
            return [NSURL URLWithString:@"http://wbur-sc.streamguys.com/wbur.aac"];
    }
}

- (NSDictionary *)mediaItemProperties;
{
    return [NSDictionary dictionary];
}

- (NSTimeInterval) playbackCursorPosition;
{
    return 0;
}

- (NSTimeInterval) duration;
{
    return 0;
}

- (BOOL) isEqualToPlayable:(id<PRXPlayable>)playable
{
    return [self.audioURL.absoluteString isEqualToString:playable.audioURL.absoluteString];
}


- (void) setDuration:(NSTimeInterval)duration;
{
    
}

- (void) setPlaybackCursorPosition:(NSTimeInterval)playbackCursorPosition;
{
    
}

@end
