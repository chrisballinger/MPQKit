//
//  NSDateNTFSAdditions.h
//  MPQKit
//
//  Created by Jean-Francois Roy on Thu Jan 15 2004.
//  Copyright (c) 2004-2007 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSDate (NTFSAdditions)
+ (id)dateWithNTFSFiletime:(int64_t)filetime;
- (int64_t)ntfsFiletime;
@end
