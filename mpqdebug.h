/*
 *  mpqdebug.h
 *  MPQKit
 *
 *  Created by Anarchie on Wed Jun 11 2003.
 *  Copyright (c) 2003-2007 MacStorm. All rights reserved.
 *
 */

#if defined(DEBUG)
static inline void MPQDebugLog(NSString* format, ...) {
    va_list va;
    va_start(va, format);
    NSLogv(format, va);
    va_end(va);
}

#if DEBUG > 1
static inline void MPQDebugLog2(NSString* format, ...) {
    va_list va;
    va_start(va, format);
    NSLogv(format, va);
    va_end(va);
}
#else
static inline void MPQDebugLog2(NSString* format, ...) {

}
#endif

#else
static inline void MPQDebugLog(NSString* format, ...) {

}

static inline void MPQDebugLog2(NSString* format, ...) {

}
#endif
