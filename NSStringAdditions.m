//
//  NSStringAdditions.m
//  MPQKit
//
//  Created by Jean-Francois Roy on Fri Jul 18 2003.
//  Copyright (c) 2003-2007 MacStorm. All rights reserved.
//

#import "NSStringAdditions.h"


@implementation NSString (MPQKitAdditions)

- (NSString*)stringByReplacingBackslashWithSlash {
    NSMutableString* newStr = [self mutableCopy];
    NSRange searchRange;
    NSRange foundRange;

    searchRange = NSMakeRange(0, self.length);
    while ((searchRange.length > 0) && ((foundRange = [newStr rangeOfString:@"\\" options:NSLiteralSearch range:searchRange]).length > 0)) {
        [newStr replaceCharactersInRange:foundRange withString:@"/"];
        searchRange = NSMakeRange(NSMaxRange(foundRange), NSMaxRange(searchRange) - NSMaxRange(foundRange));
    }
    
    return newStr;
}

- (NSString*)stringByReplacingSlashWithBackslash {
    NSMutableString* newStr = [self mutableCopy];
    NSRange searchRange;
    NSRange foundRange;

    searchRange = NSMakeRange(0, self.length);
    while ((searchRange.length > 0) && ((foundRange = [newStr rangeOfString:@"/" options:NSLiteralSearch range:searchRange]).length > 0)) {
        [newStr replaceCharactersInRange:foundRange withString:@"\\"];
        searchRange = NSMakeRange(NSMaxRange(foundRange), NSMaxRange(searchRange) - NSMaxRange(foundRange));
    }
    
    return newStr;
}

@end
