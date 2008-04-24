//
//  NSArrayAdditions.h
//  MPQKit
//
//  Created by Jean-François Roy on 13/10/2006.
//  Copyright 2006 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSArray (ListfileAdditions)
+ (id)arrayWithListfileData:(NSData*)listfileData;
@end

@interface NSMutableArray (ListfileAdditions)
+ (id)arrayWithListfileData:(NSData*)listfileData;
- (id)initWithListfileData:(NSData*)listfileData;
- (void)sortAndDeleteDuplicates;
@end
