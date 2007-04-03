//
//  NSStringAdditions.h
//  MPQKit
//
//  Created by Jean-Francois Roy on Fri Jul 18 2003.
//  Copyright (c) 2003 MacStorm. All rights reserved.
//

#import <Foundation/NSString.h>


@interface NSString (MPQKitAdditions)
- (NSString *)stringByReplacingBackslashWithSlash;
- (NSString *)stringByReplacingSlashWithBackslash;
@end
