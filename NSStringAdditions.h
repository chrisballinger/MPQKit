//
//  NSStringAdditions.h
//  MPQKit
//
//  Created by Jean-Francois Roy on Fri Jul 18 2003.
//  Copyright (c) 2003-2007 MacStorm. All rights reserved.
//

#import <Foundation/NSString.h>


@interface NSString (MPQKitAdditions)
@property (nonatomic, readonly, copy) NSString *stringByReplacingBackslashWithSlash;
@property (nonatomic, readonly, copy) NSString *stringByReplacingSlashWithBackslash;
@end
