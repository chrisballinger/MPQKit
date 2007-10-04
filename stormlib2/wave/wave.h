/*****************************************************************************/
/* Wave.h                                 Copyright (c) Ladislav Zezula 2003 */
/*---------------------------------------------------------------------------*/
/* Header file for WAVe unplode functions                                    */
/*---------------------------------------------------------------------------*/
/*   Date    Ver   Who  Comment                                              */
/* --------  ----  ---  -------                                              */
/* 31.03.03  1.00  Lad  The first version of Wave.h                          */
/*****************************************************************************/

#ifndef __WAVE_H__
#define __WAVE_H__

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

//-----------------------------------------------------------------------------
// Functions

uint32_t CompressWave(uint8_t *outBuffer, uint32_t outBufferLength, int16_t *inBuffer, uint32_t inBufferLength, uint8_t channels, uint8_t compressionLevel);
uint32_t DecompressWave(int16_t *outBuffer, uint32_t outBufferLength, uint8_t *inBuffer, uint32_t inBufferLength, uint8_t channels);

#ifdef __cplusplus
}
#endif

#endif // __WAVE_H__
