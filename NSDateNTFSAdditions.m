//
//  NSDateNTFSAdditions.m
//  MPQKit
//
//  Created by Jean-Francois Roy on Thu Jan 15 2004.
//  Copyright (c) 2004-2007 MacStorm. All rights reserved.
//

#import "NSDateNTFSAdditions.h"

/*
The FILETIME data structure is a 64-bit value representing the number of 100-nanosecond intervals since 
January 1, 1601
*/

/* Number of 100 nanosecond units from 1/1/1601 to 1/1/1970 */
static const uint64_t EPOCH_BIAS = 116444736000000000ULL;

@implementation NSDate (NTFSAdditions)

+ (id)dateWithNTFSFiletime:(int64_t)filetime {
    // We bring the filetime up to 1970
    filetime -= EPOCH_BIAS;
    
    NSTimeInterval secondsSinceEPOCH = filetime * 0.0000001;
    
    // Now we just have to convert that number of seconds to a NSDate instance
    return [NSDate dateWithTimeIntervalSince1970:secondsSinceEPOCH];
}

- (int64_t)ntfsFiletime {
    // Number of seconds between self and 1970
    NSTimeInterval secondsSince1970 = [self timeIntervalSince1970];
    
    // Now convert seconds to 100 ns units
    int64_t filetime = (int64_t)(secondsSince1970 / 0.0000001);
    
    // And finally shove us allll the way back to 1601
    return filetime + EPOCH_BIAS;
}

@end
