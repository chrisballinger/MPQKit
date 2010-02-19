/*
 *  MPQByteOrder.h
 *  MPQKit
 *
 *  Created by Jean-Francois Roy on 08/01/2008.
 *  Copyright 2008 MacStorm. All rights reserved.
 *
 */

#ifndef MPQ_BYTE_ORDER_H
#define MPQ_BYTE_ORDER_H

#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

#include <CoreFoundation/CFByteOrder.h>
#define MPQ_INLINE CF_INLINE

#define MPQSwapInt16 CFSwapInt16
#define MPQSwapInt32 CFSwapInt32
#define MPQSwapInt64 CFSwapInt64

MPQ_INLINE uint16_t MPQSwapInt16BigToHost(uint16_t arg) {
#if defined(__BIG_ENDIAN__)
    return arg;
#else
    return MPQSwapInt16(arg);
#endif
}

MPQ_INLINE uint32_t MPQSwapInt32BigToHost(uint32_t arg) {
#if defined(__BIG_ENDIAN__)
    return arg;
#else
    return MPQSwapInt32(arg);
#endif
}

MPQ_INLINE uint64_t MPQSwapInt64BigToHost(uint64_t arg) {
#if defined(__BIG_ENDIAN__)
    return arg;
#else
    return MPQSwapInt64(arg);
#endif
}

MPQ_INLINE uint16_t MPQSwapInt16HostToBig(uint16_t arg) {
#if defined(__BIG_ENDIAN__)
    return arg;
#else
    return MPQSwapInt16(arg);
#endif
}

MPQ_INLINE uint32_t MPQSwapInt32HostToBig(uint32_t arg) {
#if defined(__BIG_ENDIAN__)
    return arg;
#else
    return MPQSwapInt32(arg);
#endif
}

MPQ_INLINE uint64_t MPQSwapInt64HostToBig(uint64_t arg) {
#if defined(__BIG_ENDIAN__)
    return arg;
#else
    return MPQSwapInt64(arg);
#endif
}

MPQ_INLINE uint16_t MPQSwapInt16LittleToHost(uint16_t arg) {
#if defined(__LITTLE_ENDIAN__)
    return arg;
#else
    return MPQSwapInt16(arg);
#endif
}

MPQ_INLINE uint32_t MPQSwapInt32LittleToHost(uint32_t arg) {
#if defined(__LITTLE_ENDIAN__)
    return arg;
#else
    return MPQSwapInt32(arg);
#endif
}

MPQ_INLINE uint64_t MPQSwapInt64LittleToHost(uint64_t arg) {
#if defined(__LITTLE_ENDIAN__)
    return arg;
#else
    return MPQSwapInt64(arg);
#endif
}

MPQ_INLINE uint16_t MPQSwapInt16HostToLittle(uint16_t arg) {
#if defined(__LITTLE_ENDIAN__)
    return arg;
#else
    return MPQSwapInt16(arg);
#endif
}

MPQ_INLINE uint32_t MPQSwapInt32HostToLittle(uint32_t arg) {
#if defined(__LITTLE_ENDIAN__)
    return arg;
#else
    return MPQSwapInt32(arg);
#endif
}

MPQ_INLINE uint64_t MPQSwapInt64HostToLittle(uint64_t arg) {
#if defined(__LITTLE_ENDIAN__)
    return arg;
#else
    return MPQSwapInt64(arg);
#endif
}

#if defined(__cplusplus)
}
#endif

#endif // MPQ_BYTE_ORDER_H
