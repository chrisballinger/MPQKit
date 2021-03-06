/*****************************************************************************/
/* wave.cpp                               Copyright (c) Ladislav Zezula 2003 */
/*---------------------------------------------------------------------------*/
/* This module contains decompression methods used by Storm.dll to decompress*/
/* WAVe files. Thanks to Tom Amigo for releasing his sources.                */
/*---------------------------------------------------------------------------*/
/*   Date    Ver   Who  Comment                                              */
/* --------  ----  ---  -------                                              */
/* 11.03.03  1.00  Lad  Splitted from Pkware.cpp                             */
/* 20.05.03  2.00  Lad  Added compression                                    */
/* 19.11.03  2.01  Dan  Big endian handling                                  */
/*****************************************************************************/

#include <assert.h>
#include "MPQByteOrder.h"
#include "wave.h"

//------------------------------------------------------------------------------
// Structures

union TByteAndWordPtr
{
    int16_t* pw;
    uint8_t* pb;
};
typedef union TByteAndWordPtr TByteAndWordPtr;

union TWordAndByteArray
{
    int16_t w;
    uint8_t b[2];
};
typedef union TWordAndByteArray TWordAndByteArray;

//-----------------------------------------------------------------------------
// Tables necessary for decompression

static int32_t Table1503F120[] =
{
    0xFFFFFFFF, 0x00000000, 0xFFFFFFFF, 0x00000004, 0xFFFFFFFF, 0x00000002, 0xFFFFFFFF, 0x00000006,
    0xFFFFFFFF, 0x00000001, 0xFFFFFFFF, 0x00000005, 0xFFFFFFFF, 0x00000003, 0xFFFFFFFF, 0x00000007,
    0xFFFFFFFF, 0x00000001, 0xFFFFFFFF, 0x00000005, 0xFFFFFFFF, 0x00000003, 0xFFFFFFFF, 0x00000007,  
    0xFFFFFFFF, 0x00000002, 0xFFFFFFFF, 0x00000004, 0xFFFFFFFF, 0x00000006, 0xFFFFFFFF, 0x00000008  
};

static int32_t Table1503F1A0[] =
{
    0x00000007, 0x00000008, 0x00000009, 0x0000000A, 0x0000000B, 0x0000000C, 0x0000000D, 0x0000000E,
    0x00000010, 0x00000011, 0x00000013, 0x00000015, 0x00000017, 0x00000019, 0x0000001C, 0x0000001F,
    0x00000022, 0x00000025, 0x00000029, 0x0000002D, 0x00000032, 0x00000037, 0x0000003C, 0x00000042,
    0x00000049, 0x00000050, 0x00000058, 0x00000061, 0x0000006B, 0x00000076, 0x00000082, 0x0000008F,
    0x0000009D, 0x000000AD, 0x000000BE, 0x000000D1, 0x000000E6, 0x000000FD, 0x00000117, 0x00000133,
    0x00000151, 0x00000173, 0x00000198, 0x000001C1, 0x000001EE, 0x00000220, 0x00000256, 0x00000292,
    0x000002D4, 0x0000031C, 0x0000036C, 0x000003C3, 0x00000424, 0x0000048E, 0x00000502, 0x00000583,
    0x00000610, 0x000006AB, 0x00000756, 0x00000812, 0x000008E0, 0x000009C3, 0x00000ABD, 0x00000BD0,
    0x00000CFF, 0x00000E4C, 0x00000FBA, 0x0000114C, 0x00001307, 0x000014EE, 0x00001706, 0x00001954,
    0x00001BDC, 0x00001EA5, 0x000021B6, 0x00002515, 0x000028CA, 0x00002CDF, 0x0000315B, 0x0000364B,
    0x00003BB9, 0x000041B2, 0x00004844, 0x00004F7E, 0x00005771, 0x0000602F, 0x000069CE, 0x00007462,
    0x00007FFF
};

//----------------------------------------------------------------------------
// CompressWave

// 1500EF70
uint32_t CompressWave(uint8_t* outBuffer, uint32_t outBufferLength, int16_t* inBuffer, uint32_t inBufferLength, uint8_t channels, uint8_t compressionLevel)
{
    TByteAndWordPtr out;                                // Pointer to the output buffer
    int32_t SInt32Array1[2];
    int32_t SInt32Array2[2];
    int32_t SInt32Array3[2];
    uint32_t nBytesRemains = outBufferLength;			// Number of bytes remaining
    uint32_t nWordsRemains;                             // Number of words remaining
    uint32_t dwBitBuff;
    uint32_t dwStopBit;
    uint32_t dwBit;
    uint32_t ebx;
    uint32_t esi;
    int32_t nTableValue;
    int16_t nOneWord;
    int32_t var_1C;
    int32_t var_2C;
    int32_t nLength;
    uint32_t nIndex;
    int32_t nValue;
    
    assert((inBufferLength % 2) == 0);
    assert(channels == 1 || channels == 2);
    
    // If less than 2 bytes remain, don't decompress anything
    out.pb = outBuffer;
    if(nBytesRemains < 2)
        return 2;

    *out.pb++ = 0;
    *out.pb++ = compressionLevel - 1;
	
	if((out.pb - outBuffer + (channels * sizeof(int16_t))) > nBytesRemains)
        return (uint32_t)(out.pb - outBuffer + (channels * sizeof(int16_t)));

    SInt32Array1[0] = SInt32Array1[1] = 0x2C;

    for(uint8_t i = 0; i < channels; i++)
    {
        nOneWord = (int16_t)MPQSwapInt16LittleToHost(*inBuffer++);
        //*out.pw++ = (int16_t)MPQSwapInt16LittleToHost(nOneWord);
		*out.pw++ = *inBuffer++;
        SInt32Array2[i] = nOneWord;
    }

    // Weird. But it's there
    nLength = inBufferLength;
    if(nLength < 0)
        nLength++;

    nLength = (nLength / 2) - (uint32_t)(out.pb - outBuffer);
    nLength = (nLength < 0) ? 0 : nLength;
    
    nIndex  = channels - 1;
	// Explicit cast is OK here, function can't process more than uint32_t
    nWordsRemains = inBufferLength / (uint32_t)sizeof(int16_t);
    
    for(uint32_t chnl = channels; chnl < nWordsRemains; chnl++)
    {
        // 1500F030
        if((out.pb - outBuffer + sizeof(int16_t)) > nBytesRemains)
            return (uint32_t)(out.pb - outBuffer + sizeof(int16_t));

        // Switch index
        if(channels == 2)
            nIndex = (nIndex == 0) ? 1 : 0;

        // Load one word from the input stream
        nOneWord = (int16_t)MPQSwapInt16LittleToHost(*inBuffer++);
        SInt32Array3[nIndex] = nOneWord;
        
        nValue = nOneWord - SInt32Array2[nIndex];
        nValue = (nValue < 0) ? ((int32_t)((uint32_t)nValue ^ 0xFFFFFFFF) + 1) : nValue;

        ebx = (nOneWord >= SInt32Array2[nIndex]) ? 0 : 0x40;

        nTableValue = Table1503F1A0[SInt32Array1[nIndex]];
        dwStopBit = compressionLevel;

        if(nValue < (nTableValue >> compressionLevel))
        {
            if(SInt32Array1[nIndex] != 0)
                SInt32Array1[nIndex]--;
            *out.pb++ = 0x80;
        }
        else
        {
            while(nValue > nTableValue * 2)
            {
                if(SInt32Array1[nIndex] >= 0x58 || nLength == 0)
                    break;

                SInt32Array1[nIndex] += 8;
                if(SInt32Array1[nIndex] > 0x58)
                    SInt32Array1[nIndex] = 0x58;

                nTableValue = Table1503F1A0[SInt32Array1[nIndex]];
                *out.pb++ = 0x81;
                nLength--;
            }

            var_2C = nTableValue >> (compressionLevel - 1);
            dwBitBuff = 0;

            esi = (1 << (dwStopBit - 2));
            dwStopBit = (esi <= 0x20) ? esi : 0x20;

            for(var_1C = 0, dwBit = 1; ; dwBit <<= 1)
            {
//              esi = var_1C + nTableValue;
                if((var_1C + nTableValue) <= nValue)
                {
                    var_1C += nTableValue;
                    dwBitBuff |= dwBit;
                }
                if(dwBit == dwStopBit)
                    break;
               
                nTableValue >>= 1;
            }

            nValue = SInt32Array2[nIndex];
            if(ebx != 0)
            {
                nValue -= (var_1C + var_2C);
                if(nValue < -32768)
                    nValue = -32768;
            }
            else
            {
                nValue += (var_1C + var_2C);
                if(nValue > 32767)
                    nValue = 32767;
            }

            SInt32Array2[nIndex]  = nValue;
            *out.pb++ = (uint8_t)(dwBitBuff | ebx);
            nTableValue = Table1503F120[dwBitBuff & 0x1F];
            SInt32Array1[nIndex]  = SInt32Array1[nIndex] + nTableValue; 
            if(SInt32Array1[nIndex] < 0)
                SInt32Array1[nIndex] = 0;
            else if(SInt32Array1[nIndex] > 0x58)
                SInt32Array1[nIndex] = 0x58;
        }
    }

    return (uint32_t)(out.pb - outBuffer);
}

//----------------------------------------------------------------------------
// DecompressWave

// 1500F230
uint32_t DecompressWave(int16_t* outBuffer, uint32_t outBufferLength, uint8_t* inBuffer, uint32_t inBufferLength, uint8_t channels)
{
    TByteAndWordPtr out;                // Output buffer
    TByteAndWordPtr in;
    uint8_t* pbInBufferEnd = (inBuffer + inBufferLength);
    int32_t SInt32Array1[2];
    int32_t SInt32Array2[2];
    int16_t nOneWord;
    uint32_t dwOutLengthCopy = outBufferLength;
    uint32_t nIndex;
    
    assert((outBufferLength % 2) == 0);
    assert(channels == 1 || channels == 2);
    
    SInt32Array1[0] = SInt32Array1[1] = 0x2C;
    out.pw = outBuffer;
    in.pb = inBuffer;
    in.pw++;

    // Fill the Uint32Array2 array by channel values.
    for(uint8_t i = 0; i < channels; i++)
    {
        nOneWord = (int16_t)MPQSwapInt16LittleToHost(*in.pw);
        SInt32Array2[i] = nOneWord;
        if(dwOutLengthCopy < 2)
            return (uint32_t)(out.pb - (uint8_t*)outBuffer);

        *out.pw++ = *in.pw++;
		// Explicit cast is OK here
        dwOutLengthCopy -= (uint32_t)sizeof(int16_t);
    }

    // Get the initial index
    nIndex = channels - 1;

    // Perform the decompression
    while(in.pb < pbInBufferEnd)
    {
        uint8_t nOneByte = *in.pb++;

        // Switch index
        if(channels == 2)
            nIndex = (nIndex == 0) ? 1 : 0;

        // 1500F2A2: Get one byte from input buffer
        if(nOneByte & 0x80)
        {
            switch(nOneByte & 0x7F)
            {
                case 0:     // 1500F315
                    if(SInt32Array1[nIndex] != 0)
                        SInt32Array1[nIndex]--;

                    if(dwOutLengthCopy < 2)
                        return (uint32_t)(out.pb - (uint8_t*)outBuffer);

                    *out.pw++ = (int16_t)MPQSwapInt16HostToLittle(SInt32Array2[nIndex]);
					// Explicit cast is OK here
                    outBufferLength -= (uint32_t)sizeof(int16_t);
                    break;

                case 1:     // 1500F2E8
                    SInt32Array1[nIndex] += 8;
                    if(SInt32Array1[nIndex] > 0x58)
                        SInt32Array1[nIndex] = 0x58;
                    
                    if(channels == 2)
                        nIndex = (nIndex == 0) ? 1 : 0;
                    break;

                case 2:     // 1500F41E
                    break;

                default:    // 1500F2C4
                    SInt32Array1[nIndex] -= 8;
                    if(SInt32Array1[nIndex] < 0)
                        SInt32Array1[nIndex] = 0;

                    if(channels == 2)
                        nIndex = (nIndex == 0) ? 1 : 0;
                    break;
            }
        }
        else
        {
            // 1500F349
            int32_t temp1 = Table1503F1A0[SInt32Array1[nIndex]];    // EDI
            int32_t temp2 = temp1 >> inBuffer[1];                // ESI
            int32_t temp3 = SInt32Array2[nIndex];                   // ECX

            if(nOneByte & 0x01)          // EBX = nOneByte
                temp2 += (temp1 >> 0);

            if(nOneByte & 0x02)
                temp2 += (temp1 >> 1);

            if(nOneByte & 0x04)
                temp2 += (temp1 >> 2);

            if(nOneByte & 0x08)
                temp2 += (temp1 >> 3);

            if(nOneByte & 0x10)
                temp2 += (temp1 >> 4);

            if(nOneByte & 0x20)
                temp2 += (temp1 >> 5);

            if(nOneByte & 0x40)
            {
                temp3 = temp3 - temp2;
                if(temp3 <= -32768)
                    temp3 = -32768;
            }
            else
            {
                temp3 = temp3 + temp2;
                if(temp3 >= 32767)
                    temp3 = 32767;
            }

            SInt32Array2[nIndex] = temp3;
            if(outBufferLength < 2)
                break;

            // Store the output 16-bit value
            *out.pw++ = (int16_t)MPQSwapInt16HostToLittle(SInt32Array2[nIndex]);
			// Explicit cast is OK here
            outBufferLength -= (uint32_t)sizeof(int16_t);

            SInt32Array1[nIndex] += Table1503F120[nOneByte & 0x1F];

            if(SInt32Array1[nIndex] < 0)
                SInt32Array1[nIndex] = 0;
            else if(SInt32Array1[nIndex] > 0x58)
                SInt32Array1[nIndex] = 0x58;
        }
    }
    return (uint32_t)(out.pb - (uint8_t*)outBuffer);
}
