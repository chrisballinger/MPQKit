/*
 *  MPQKitPrivate.h
 *  MPQKit
 *
 *  Created by Jean-Francois Roy on 7/27/07.
 *  Copyright 2007 MacStorm. All rights reserved.
 *
 */

#import <MPQKit/MPQKit.h>

#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
#define MPQNSInteger long
#define MPQNSUInteger unsigned long
#else
#define MPQNSInteger NSInteger
#define MPQNSUInteger NSUInteger
#endif

#import <MPQKit/MPQArchivePrivate.h>

extern char* _MPQCreateASCIIFilename(NSString* filename, NSError **error);
