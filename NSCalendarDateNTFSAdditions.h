//
//  NSCalendarDateNTFSAdditions.h
//  MPQKit
//
//  Created by Jean-Francois Roy on Thu Jan 15 2004.
//  Copyright (c) 2004 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSCalendarDate (NTFSAdditions)
+ (id)dateWithNTFSDate:(int64_t)filetime;
- (int64_t)ntfsFiletime;
@end
