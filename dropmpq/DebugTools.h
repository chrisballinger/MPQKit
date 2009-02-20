/*
 *  DebugTools.h
 *  MPQDraft
 *
 *  Created by Anarchie on Sun May 18 2003.
 *  Copyright (c) 2003 MacStorm. All rights reserved.
 *
 */

#import <Foundation/NSObjCRuntime.h>
#import <stdarg.h>

#ifdef DEBUG
#define NSDebugLog NSLog
#define NSDebugLogv NSLogv
#else
#define NSDebugLog
#define NSDebugLogv
#endif

#ifdef DEBUG
#ifndef DEBUG_WARNING
#define DEBUG_WARNING
#endif
#endif
