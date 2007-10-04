/*
 *  mpqdebug.h
 *  MPQKit
 *
 *  Created by Anarchie on Wed Jun 11 2003.
 *  Copyright (c) 2003-2007 MacStorm. All rights reserved.
 *
 */

#if defined(DEBUG)
static inline void MPQDebugLog(NSString * x, ...) {
    va_list va;
    va_start(va, x);
    NSLogv(x, va);
    va_end(va);
}
#else
static inline void MPQDebugLog(NSString * x, ...) {

}
#endif
