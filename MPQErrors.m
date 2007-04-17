/*
 *  MPQErrors.c
 *  MPQKit
 *
 *  Created by Jean-François Roy on 30/12/2006.
 *  Copyright 2006 MacStorm. All rights reserved.
 *
 */

#import "MPQErrors.h"

NSString *const MPQErrorDomain = @"MPQErrorDomain";

inline void MPQTransferErrorAndDrainPool(NSError **error, NSAutoreleasePool *p) {
    NSError *e = (error) ? *error : nil;
    [e retain];
    [p release];
    [e autorelease];
}
