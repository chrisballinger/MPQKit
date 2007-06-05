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

int Decompress_pklib(void *outputBuffer, uint32_t *outputBufferLength, void *inputBuffer, uint32_t inputBufferLength);

int SCompDecompress(uint8_t *outputBuffer, uint32_t *ouputBufferLength, uint8_t *inputBuffer, uint32_t inputBufferLength);
int SCompCompress(char* pbCompressed, int* pdwOutLength, char* pbUncompressed, int dwInLength, int uCompressions, int nCmpType, int nCmpLevel);

#ifdef __cplusplus
}
#endif

#endif // __SCOMPRESSION_H__
