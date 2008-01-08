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

#if defined(__APPLE__)
#include <CoreFoundation/CFByteOrder.h>
#define MPQ_INLINE CF_INLINE

MPQ_INLINE uint16_t MPQSwapInt16(uint16_t arg) {return CFSwapInt16(arg);}
MPQ_INLINE uint32_t MPQSwapInt32(uint32_t arg) {return CFSwapInt32(arg);}
MPQ_INLINE uint64_t MPQSwapInt64(uint64_t arg) {return CFSwapInt64(arg);}

#else
#define MPQ_INLINE static __inline__

MPQ_INLINE uint16_t MPQSwapInt16(uint16_t arg) {
    uint16_t result;
    result = (uint16_t)(((arg << 8) & 0xFF00) | ((arg >> 8) & 0xFF));
    return result;
}

MPQ_INLINE uint32_t MPQSwapInt32(uint32_t arg) {
    uint32_t result;
    result = ((arg & 0xFF) << 24) | ((arg & 0xFF00) << 8) | ((arg >> 8) & 0xFF00) | ((arg >> 24) & 0xFF);
    return result;
}

MPQ_INLINE uint64_t MPQSwapInt64(uint64_t arg) {
    union mpq_swap {
        uint64_t sv;
        uint32_t ul[2];
    } tmp, result;
    tmp.sv = arg;
    result.ul[0] = MPQSwapInt32(tmp.ul[1]); 
    result.ul[1] = MPQSwapInt32(tmp.ul[0]);
    return result.sv;
}

#endif // __APPLE__

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
