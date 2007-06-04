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

#ifdef __cplusplus
extern "C" {
#endif

int32_t Decompress_pklib(uint8_t* pbOutBuffer, int32_t* pdwOutLength, uint8_t* pbInBuffer, int32_t dwInLength);

int32_t SCompDecompress(uint8_t* pbOutBuffer, int32_t* pdwOutLength, uint8_t* pbInBuffer, int32_t dwInLength);
int SCompCompress(char* pbCompressed, int* pdwOutLength, char* pbUncompressed, int dwInLength, int uCompressions, int nCmpType, int nCmpLevel);

#ifdef __cplusplus
}
#endif

#endif // __SCOMPRESSION_H__
