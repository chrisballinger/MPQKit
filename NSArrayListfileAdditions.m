//
//  NSArrayAdditions.m
//  MPQKit
//
//  Created by Jean-François Roy on 13/10/2006.
//  Copyright 2006 MacStorm. All rights reserved.
//

#import "NSArrayListfileAdditions.h"


@implementation NSArray (ListfileAdditions)

+ (id)arrayWithListfileData:(NSData*)listfileData {
    NSParameterAssert(listfileData != nil);
    
    // What we are doing to do here is extract all the lines from stringData and add an entry for each of those lines
    NSMutableString *listfileString = [[NSMutableString alloc] initWithData:listfileData encoding:NSASCIIStringEncoding];
    [listfileString replaceOccurrencesOfString:@"\r\n" withString:@"\n" options:NSLiteralSearch | NSCaseInsensitiveSearch range:NSMakeRange(0, [listfileString length])];
    [listfileString replaceOccurrencesOfString:@"\r" withString:@"\n" options:NSLiteralSearch | NSCaseInsensitiveSearch range:NSMakeRange(0, [listfileString length])];
    
    NSArray *listfileArray = [listfileString componentsSeparatedByString:@"\n"];
    [listfileString release];
    return listfileArray;
}

@end

@implementation NSMutableArray (ListfileAdditions)

+ (id)arrayWithListfileData:(NSData*)listfileData {
    return [[[[self class] alloc] initWithListfileData:listfileData] autorelease];
}

- (id)initWithListfileData:(NSData*)listfileData {
    NSParameterAssert(listfileData != nil);
    
    NSArray *returnArray = [NSArray arrayWithListfileData:listfileData];
    self = [self initWithCapacity:[returnArray count]];
    [self setArray:returnArray];
    
    if ([[self lastObject] isEqualToString:@""]) [self removeLastObject];
    
    return self;
}

- (void)sortAndDeleteDuplicates {
    [self sortUsingSelector:@selector(caseInsensitiveCompare:)];
    
    if ([self count] > 1) {
        uint32_t i = 0;
        for (; i < [self count] - 1; i++) {
            if ([[self objectAtIndex:i] caseInsensitiveCompare:[self objectAtIndex:(i+1)]] == NSOrderedSame) {
                [self removeObjectAtIndex:i];
                i--;
            }
        }
    }
}

@end
