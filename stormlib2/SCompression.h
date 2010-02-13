/*
 *  SCompression.h
 *  MPQKit
 *
 *  Created by Jean-Francois Roy on Fri Jun 20 2003.
 *  Copyright (c) 2003-2007 MacStorm. All rights reserved.
 *
 */

#ifndef __SCOMPRESSION_H__
#define __SCOMPRESSION_H__

#include <stdint.h>
#include <MPQKit/MPQSharedConstants.h>

#ifdef __cplusplus
extern "C" {
#endif

int Decompress_pklib(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength);

int SCompDecompress(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength);
int SCompCompress(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength, MPQCompressorFlag compressors, int32_t compressionType, int32_t compressionLevel);

#ifdef __cplusplus
}
#endif

#endif // __SCOMPRESSION_H__
