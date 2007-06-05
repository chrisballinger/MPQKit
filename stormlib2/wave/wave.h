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

int CompressWave(unsigned char * pbOutBuffer, int dwOutLength, short * pwInBuffer, int dwInLength, int nChannels, int nCmpLevel);
uint32_t DecompressWave(uint8_t *outputBuffer, uint32_t outputBufferLength, uint8_t *inputBuffer, uint32_t inputBufferLength, uint8_t channels);

#ifdef __cplusplus
}
#endif

#endif // __WAVE_H__
