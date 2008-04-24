//
//  _MPQFileInfoEnumerator.m
//  MPQKit
//
//  Created by Anarchie on Fri Oct 18 2002.
//  Copyright (c) 2002-2007 MacStorm. All rights reserved.
//

#import "MPQArchive.h"
#import "MPQFileInfoEnumerator.h"


@interface MPQArchive (Private)
- (NSDictionary*)_nextFileInfo:(uint32_t*)hash_position;
@end

@implementation _MPQFileInfoEnumerator

+ (id)enumeratorWithArchive:(MPQArchive*)archive {
    return [[[_MPQFileInfoEnumerator alloc] initWithArchive:archive] autorelease];
}

- (id)initWithArchive:(MPQArchive*)archive {
    self = [super init];
    if (!self) return nil;
    
    _position = 0;
    _archive = archive;
    [_archive retain];
    return self;
}

- (void)dealloc {
    [_archive release];
    [super dealloc];
}

- (id)nextObject {
    return [_archive _nextFileInfo:&_position];
}

- (NSArray*)allObjects {
    id obj;
    NSMutableArray *arr = [NSMutableArray array];
    while ((obj = [self nextObject])) [arr addObject:obj];
    return [NSArray arrayWithArray:arr];
}

@end
