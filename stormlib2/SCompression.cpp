/*****************************************************************************/
/* SCompression.cpp                       Copyright (c) Ladislav Zezula 2003 */
/*---------------------------------------------------------------------------*/
/* This module serves as a bridge between StormLib code and (de)compression  */
/* functions. All (de)compression calls go (and should only go) through this */   
/* module. No system headers should be included in this module to prevent    */
/* compile-time problems.                                                    */
/*---------------------------------------------------------------------------*/
/*   Date    Ver   Who  Comment                                              */
/* --------  ----  ---  -------                                              */
/* 01.04.03  1.00  Lad  The first version of SCompression.cpp                */
/* 19.11.03  1.01  Dan  Big endian handling                                  */
/*****************************************************************************/

#include <stdlib.h>
#include <string.h>
#include <zlib.h>
#include <bzlib.h>

#include "SCompression.h"

#include "pklib/pklib.h" 
#include "huffman/huff.h"  
#include "wave/wave.h"

#ifndef max
	#define max(a,b) ((a)>(b)?(a):(b))
#endif
#ifndef min
	#define min(a,b) ((a)<(b)?(a):(b))
#endif

//-----------------------------------------------------------------------------
// Local structures

// Information about the input and output buffers for pklib
typedef struct
{
    char   * pInBuff;                   // Pointer to input data buffer
    uint32_t nInPos;                    // Current offset in input data buffer
    uint32_t nInBytes;                  // Number of bytes in the input buffer
    char   * pOutBuff;                  // Pointer to output data buffer
    uint32_t nOutPos;                   // Position in the output buffer
    uint32_t nMaxOut;                   // Maximum number of bytes in the output buffer
} TDataInfo;

// Table of compression functions
typedef int (*COMPRESS)(char *, int *, char *, int, int *, int);
typedef struct  
{
    uint32_t mask;                      // Compression mask
    COMPRESS Compress;                  // Compression function
} TCompressTable;

// Table of decompression functions
typedef int (*DECOMPRESS)(void *, uint32_t *, void *, uint32_t);
typedef struct
{
    uint32_t   mask;                    // Decompression bit
    DECOMPRESS Decompress;              // Decompression function
} TDecompressTable;


/*****************************************************************************/
/*                                                                           */
/*  Support functions for Pkware Data Compression Library                    */
/*                                                                           */
/*****************************************************************************/

// Function loads data from the input buffer. Used by Pklib's "pk_implode"
// and "pk_explode" function as user-defined callback
// Returns number of bytes loaded
//    
//   char * buf          - Pointer to a buffer where to store loaded data
//   unsigned int * size - Max. number of bytes to read
//   void * param        - Custom pointer, parameter of pk_implode/pk_explode

static unsigned int ReadInputData(char * buf, unsigned int * size, void * param)
{
    TDataInfo * pInfo = (TDataInfo *)param;
    unsigned int nMaxAvail = (pInfo->nInBytes - pInfo->nInPos);
    unsigned int nToRead = *size;

    // Check the case when not enough data available
    if(nToRead > nMaxAvail)
        nToRead = nMaxAvail;
    
    // Load data and increment offsets
    memcpy(buf, pInfo->pInBuff + pInfo->nInPos, nToRead);
    pInfo->nInPos += nToRead;

    return nToRead;
}

// Function for store output data. Used by Pklib's "pk_implode" and "pk_explode"
// as user-defined callback
//    
//   char * buf          - Pointer to data to be written
//   unsigned int * size - Number of bytes to write
//   void * param        - Custom pointer, parameter of pk_implode/pk_explode

static void WriteOutputData(char * buf, unsigned int * size, void * param)
{
    TDataInfo * pInfo = (TDataInfo *)param;
    unsigned int nMaxWrite = (pInfo->nMaxOut - pInfo->nOutPos);
    unsigned int nToWrite = *size;

    // Check the case when not enough space in the output buffer
    if(nToWrite > nMaxWrite)
        nToWrite = nMaxWrite;

    // Write output data and increments offsets
    memcpy(pInfo->pOutBuff + pInfo->nOutPos, buf, nToWrite);
    pInfo->nOutPos += nToWrite;
}

/*****************************************************************************/
/*                                                                           */
/*  "80" is IMA ADPCM stereo (de)compression                                 */
/*  "40" is IMA ADPCM mono (de)compression                                   */
/*                                                                           */
/*****************************************************************************/

int Compress_adpcm_mono(char * pbOutBuffer, int * pdwOutLength, char * pbInBuffer, int dwInLength, int * pCmpType, int nCmpLevel)
{
    // Prepare the compression level for the next compression
    // (After us, the Huffman compression will be called)
    if(0 < nCmpLevel && nCmpLevel <= 2)
    {
        nCmpLevel = 4;
        *pCmpType = 6;
    }
    else if(nCmpLevel == 3)
    {
        nCmpLevel = 6;
        *pCmpType = 8;
    }
    else
    {
        nCmpLevel = 5;
        *pCmpType = 7;
    }
    *pdwOutLength = CompressWave((unsigned char *)pbOutBuffer, *pdwOutLength, (short *)pbInBuffer, dwInLength, 1, nCmpLevel);
    return 1;
}

int Decompress_adpcm_mono(void *outputBuffer, uint32_t *outputBufferLength, void *inputBuffer, uint32_t inputBufferLength) {
    *outputBufferLength = DecompressWave((uint8_t *)outputBuffer, *outputBufferLength, (uint8_t *)inputBuffer, inputBufferLength, 1);
    return 1;
}

int Compress_adpcm_stereo(char * pbOutBuffer, int * pdwOutLength, char * pbInBuffer, int dwInLength, int * pCmpType, int nCmpLevel)
{
    // Prepare the compression type for the next compression
    // (After us, the Huffman compression will be called)
    if(0 < nCmpLevel && nCmpLevel <= 2)
    {
        nCmpLevel = 4;
        *pCmpType = 6;
    }
    else if(nCmpLevel == 3)
    {
        nCmpLevel = 6;
        *pCmpType = 8;
    }
    else
    {
        nCmpLevel = 5;
        *pCmpType = 7;
    }
    *pdwOutLength = CompressWave((unsigned char *)pbOutBuffer, *pdwOutLength, (short *)pbInBuffer, dwInLength, 2, nCmpLevel);
    return 1;
}

int Decompress_adpcm_stereo(void *outputBuffer, uint32_t *outputBufferLength, void *inputBuffer, uint32_t inputBufferLength) {
    *outputBufferLength = DecompressWave((uint8_t *)outputBuffer, *outputBufferLength, (uint8_t *)inputBuffer, inputBufferLength, 2);
    return 1;
}

/*****************************************************************************/
/*                                                                           */
/*  The "01" (de)compression is the Huffman (?) (de)compression              */
/*                                                                           */
/*****************************************************************************/

int Compress_huff(char * pbOutBuffer, int * pdwOutLength, char * pbInBuffer, int dwInLength, int * pCmpType, int /* nCmpLevel */) {
    THuffmanTree *ht = THuffmanTree::AllocateTree();
    TOutputStream os;

    // Initialize output stream
    os.pbOutBuffer = (unsigned char *)pbOutBuffer;
    os.dwOutSize   = *pdwOutLength;
    os.pbOutPos    = (unsigned char *)pbOutBuffer;
    os.dwBitBuff   = 0;
    os.nBits       = 0;

    // Initialize the Huffman tree for compression
    ht->InitTree(true);

    *pdwOutLength = ht->DoCompression(&os, (unsigned char *)pbInBuffer, dwInLength, *pCmpType);

    delete ht;
    return 1;
}

int Decompress_huff(void *outputBuffer, uint32_t *outputBufferLength, void *inputBuffer, uint32_t inputBufferLength) {
    THuffmanTree *ht = THuffmanTree::AllocateTree();
    TInputStream is((uint8_t *)inputBuffer, inputBufferLength);

    // Initialize the Huffman tree for decompression
    ht->InitTree(false);

    *outputBufferLength = ht->DoDecompression((uint8_t *)outputBuffer, *outputBufferLength, &is);
    
    delete ht;
    return 1;
}

/*****************************************************************************/
/*                                                                           */
/*  The "02" (de)compression is the ZLIB (de)compression                     */
/*                                                                           */
/*****************************************************************************/

int Compress_zlib(char * pbOutBuffer, int * pdwOutLength, char * pbInBuffer, int dwInLength, int * /* pCmpType */, int nCmpLevel)
{
    z_stream z;                        // Stream information for zlib
    int nResult;
    
    // Fill the stream structure for zlib
    z.next_in   = (Bytef *)pbInBuffer;
    z.avail_in  = (uInt)dwInLength;
    z.total_in  = dwInLength;
    z.next_out  = (Bytef *)pbOutBuffer;
    z.avail_out = *pdwOutLength;
    z.total_out = 0;
    z.zalloc    = NULL;
    z.zfree     = NULL;
    
    // Initialize the compression structure. Storm.dll uses zlib version 1.1.3
    *pdwOutLength = 0;
    if((nResult = deflateInit(&z, nCmpLevel)) == 0)
    {
        // Call zlib to compress the data
        nResult = deflate(&z, Z_FINISH);
        
        if(nResult == Z_OK || nResult == Z_STREAM_END)
            *pdwOutLength = z.total_out;
        
        deflateEnd(&z);
    }
    return nResult;
}

int Decompress_zlib(void *outputBuffer, uint32_t *outputBufferLength, void *inputBuffer, uint32_t inputBufferLength) {
    z_stream z;                        // Stream information for zlib
    int nResult;

    // Fill the stream structure for zlib
    z.next_in   = (Bytef *)inputBuffer;
    z.avail_in  = inputBufferLength;
    z.total_in  = inputBufferLength;
    z.next_out  = (Bytef *)outputBuffer;
    z.avail_out = *outputBufferLength;
    z.total_out = 0;
    z.zalloc    = NULL;
    z.zfree     = NULL;

    // Initialize the decompression structure. Storm.dll uses zlib version 1.1.3
    if ((nResult = inflateInit(&z)) == 0) {
        // Call zlib to decompress the data
        nResult = inflate(&z, Z_FINISH);
        *outputBufferLength = z.total_out;
        inflateEnd(&z);
    }
    return nResult;
}

/*****************************************************************************/
/*                                                                           */
/*  The "08" (de)compression is the Pkware DCL (de)compression               */
/*                                                                           */
/*****************************************************************************/

int Compress_pklib(char * pbOutBuffer, int * pdwOutLength, char * pbInBuffer, int dwInLength, int * pCmpType, int /* nCmpLevel */)
{
    TDataInfo Info;                     // Data information
    char work_buf[CMP_BUFFER_SIZE];     // Pklib's work buffer
    unsigned int dict_size;             // Dictionary size
    unsigned int ctype;                 // Compression type

    // Fill data information structure
    Info.pInBuff  = pbInBuffer;
    Info.nInPos   = 0;
    Info.nInBytes = dwInLength;
    Info.pOutBuff = pbOutBuffer;
    Info.nOutPos  = 0;
    Info.nMaxOut  = *pdwOutLength;

    // Set the compression type and dictionary size
    ctype = (*pCmpType == 2) ? CMP_ASCII : CMP_BINARY;
    if (dwInLength < 0x600)
        dict_size = 0x400;
    else if(0x600 <= dwInLength && dwInLength < 0xC00)
        dict_size = 0x800;
    else
        dict_size = 0x1000;

    // Do the compression
    pk_implode(ReadInputData, WriteOutputData, work_buf, &Info, &ctype, &dict_size);
    *pdwOutLength = Info.nOutPos;
    return 1;
}

int Decompress_pklib(void *outputBuffer, uint32_t *outputBufferLength, void *inputBuffer, uint32_t inputBufferLength) {
    TDataInfo Info;                     // Data information
    char work_buf[EXP_BUFFER_SIZE];     // Pklib's work buffer

    // Fill data information structure
    Info.pInBuff  = (char *)inputBuffer;
    Info.nInPos   = 0;
    Info.nInBytes = inputBufferLength;
    Info.pOutBuff = (char *)outputBuffer;
    Info.nOutPos  = 0;
    Info.nMaxOut  = *outputBufferLength;

    // Do the decompression
    pk_explode(ReadInputData, WriteOutputData, work_buf, &Info);
    
    // Fix : If PKLIB is unable to decompress the data, they are uncompressed
    if (Info.nOutPos == 0) {
        Info.nOutPos = min(*outputBufferLength, inputBufferLength);
        memcpy(outputBuffer, inputBuffer, Info.nOutPos);
    }

    *outputBufferLength = Info.nOutPos;
	return 1;
}

/*****************************************************************************/
/*                                                                           */
/*  The "10" (de)compression is the bzip2 (de)compression                     */
/*                                                                           */
/*****************************************************************************/

int Compress_bz2(char * pbOutBuffer, int * pdwOutLength, char * pbInBuffer, int dwInLength, int * /* pCmpType */, int nCmpLevel) {
    bz_stream s;                        // Stream information for bz2
    int nResult;
	
	s.bzalloc = NULL;
	s.bzfree = NULL;
	s.opaque = NULL;
	
	// Initialize the output length
	*pdwOutLength = 0;
	
	// init bz2 for compression
	nResult = BZ2_bzCompressInit(&s, nCmpLevel, 0, 0);
	if (nResult != BZ_OK) return 0;
	
	// Fill the stream structure for bz2
    s.next_in   = pbInBuffer;
    s.avail_in  = (unsigned int)dwInLength;
    s.next_out  = pbOutBuffer;
    s.avail_out = *((unsigned int *)pdwOutLength);
	
	// Call bz2 to compress the data
    do {
        nResult = BZ2_bzCompress(&s, (s.avail_in != 0) ? BZ_RUN : BZ_FINISH);
    } while (nResult == BZ_RUN_OK || nResult == BZ_FLUSH_OK || nResult == BZ_FINISH_OK);
    
	// Finalize the compression
	BZ2_bzCompressEnd(&s);
	*pdwOutLength = s.total_out_lo32;
	
    return (nResult == BZ_STREAM_END) ? 1 : 0;
}

int Decompress_bz2(void *outputBuffer, uint32_t *outputBufferLength, void *inputBuffer, uint32_t inputBufferLength) {
	bz_stream s;	// Stream information for bz2
    int nResult;
	
	s.bzalloc = NULL;
	s.bzfree = NULL;
	s.opaque = NULL;
	
    // Initialize the output length
	*outputBufferLength = 0;
    
	// init bz2 for decompression
	nResult = BZ2_bzDecompressInit(&s, 0, 0);
	if (nResult != BZ_OK) return 0;

    // Fill the stream structure for bz2
    s.next_in   = (char *)inputBuffer;
    s.avail_in  = inputBufferLength;
    s.next_out  = (char *)outputBuffer;
    s.avail_out = *outputBufferLength;

	// Call bz2 to decompress the data
    do {
        nResult = BZ2_bzDecompress(&s);
    } while (nResult == BZ_OK);
	
    BZ2_bzDecompressEnd(&s);
    *outputBufferLength = s.total_out_lo32;
    
    return (nResult == BZ_STREAM_END) ? 1 : 0;
}

/*****************************************************************************/
/*                                                                           */
/*   SCompCompress                                                           */
/*                                                                           */
/*****************************************************************************/

// This table contains compress functions which can be applied to
// uncompressed blocks. Each bit set means the corresponding
// compression method/function must be applied.
//
//   WAVes compression            Data compression
//   ------------------           -------------------
//   1st block   - 0x08           0x08 (D, HF, W2, SC, D2)
//   Rest blocks - 0x81           0x02 (W3)

static TCompressTable cmp_table[] =
{
    {0x40, Compress_adpcm_mono},        // Mono ADPCM
    {0x80, Compress_adpcm_stereo},      // Stereo ADPCM
    {0x01, Compress_huff},              // Huffman
    {0x02, Compress_zlib},              // zlib
    {0x08, Compress_pklib},             // Pkware Data Compression Library
    {0x10, Compress_bz2}                // bzip2
};

int SCompCompress(char* pbCompressed, int* pdwOutLength, char* pbUncompressed, int dwInLength, int uCompressions, int nCmpType, int nCmpLevel)
{
    char * pbTempBuff = NULL;           // Temporary storage for decompressed data
    char * pbOutput = pbCompressed;     // Current output buffer
    char * pbInput;                     // Current input buffer
    int uCompressions2;
    int dwCompressCount = 0;
    int dwDoneCount = 0;
    int dwOutSize = 0;
    int dwInSize  = dwInLength;
    int dwEntries = (sizeof(cmp_table) / sizeof(TCompressTable));
    int nResult = 1;
    int i;       

    // Check for valid parameters
    if(!pdwOutLength || *pdwOutLength < dwInLength || !pbCompressed || !pbUncompressed)
    {
        return 0;
    }

    // Count the compressions
    for(i = 0, uCompressions2 = uCompressions; i < dwEntries; i++)
    {
        if(uCompressions & cmp_table[i].mask)
            dwCompressCount++;

        uCompressions2 &= ~cmp_table[i].mask;
    }

    // If a compression remains, do nothing
    if(uCompressions2 != 0) {
        return 0;
	}

    // If more that one compression, allocate intermediate buffer
    if(dwCompressCount >= 2) {
        pbTempBuff = new char [*pdwOutLength + 1];
	}

    // Perform the compressions
    pbInput = pbUncompressed;
    dwInSize = dwInLength;
    for(i = 0, uCompressions2 = uCompressions; i < dwEntries; i++)
    {
        if(uCompressions2 & cmp_table[i].mask)
        {
            // Set the right output buffer 
            dwCompressCount--;
            pbOutput = (dwCompressCount & 1) ? pbTempBuff : pbCompressed;

            // Perform the partial compression
            dwOutSize = *pdwOutLength - 1;

            cmp_table[i].Compress(pbOutput + 1, &dwOutSize, pbInput, dwInSize, &nCmpType, nCmpLevel);
            if(dwOutSize == 0)
            {
                *pdwOutLength = 0;
                nResult = 0;
                break;
            }

            // If the compression failed, copy the block instead
            if(dwOutSize >= dwInSize - 1)
            {
                if(dwDoneCount > 0)
                    pbOutput++;

                memcpy(pbOutput, pbInput, dwInSize);
                pbInput = pbOutput;
                uCompressions &= ~cmp_table[i].mask;
                dwOutSize = dwInSize;
            }
            else
            {
                pbInput = pbOutput + 1;
                dwInSize = dwOutSize;
                dwDoneCount++;
            }
        }
    }

    // Copy the compressed data to the correct output buffer
    if(nResult != 0)
    {
        if(uCompressions && (dwInSize + 1) < *pdwOutLength)
        {
            if(pbOutput != pbCompressed  && pbOutput != pbCompressed + 1)
                memcpy(pbCompressed, pbOutput, dwInSize);
            *pbCompressed = (char)uCompressions;
            *pdwOutLength = dwInSize + 1;
        }
        else
        {
            memmove(pbCompressed, pbUncompressed, dwInSize);
            *pdwOutLength = dwInSize;
        }
    }

    // Cleanup and return
    if(pbTempBuff != NULL) {
        delete pbTempBuff;
	}
	
    return nResult;
}

/*****************************************************************************/
/*                                                                           */
/*   SCompDecompress                                                         */
/*                                                                           */
/*****************************************************************************/

// This table contains decompress functions which can be applied to
// uncompressed blocks. The compression mask is stored in the first byte
// of compressed block
static TDecompressTable dcmp_table[] = {
    {0x10, Decompress_bz2},             // bzip2
    {0x08, Decompress_pklib},           // Pkware Data Compression Library
    {0x02, Decompress_zlib},            // zlib
    {0x01, Decompress_huff},            // Huffman
    {0x80, Decompress_adpcm_stereo},    // Stereo ADPCM
    {0x40, Decompress_adpcm_mono}       // Mono ADPCM
};

int SCompDecompress(uint8_t *outputBuffer, uint32_t *ouputBufferLength, uint8_t *inputBuffer, uint32_t inputBufferLength) {
    uint8_t *pbTempBuff = NULL;                     // Temporary storage for decompressed data
    uint8_t *pbWorkBuff = NULL;                     // Where to store decompressed data
    uint32_t dwOutLength = *ouputBufferLength;      // For storage number of output bytes
    uint8_t fDecompressions1;                       // Decompressions applied to the block
    uint8_t fDecompressions2;                       // Just another copy of decompressions applied to the block
    int32_t dwCount = 0;                            // Counter for every use
    uint32_t dwEntries = (sizeof(dcmp_table) / sizeof(TDecompressTable));
    int nResult = 1;
    uint32_t i;

    // If the input length is the same as output, do nothing.
    if(inputBufferLength == dwOutLength)
    {
        if(inputBuffer == outputBuffer)
            return 1;

        memcpy(outputBuffer, inputBuffer, inputBufferLength);
        *ouputBufferLength = inputBufferLength;
        return 1;
    }
    
    // Get applied compression types and decrement data length
    fDecompressions1 = fDecompressions2 = *inputBuffer++;
    inputBufferLength--;
    
    // Search decompression table type and get all types of compression
    for(i = 0; i < dwEntries; i++)
    {
        // We have to apply this decompression ?
        if(fDecompressions1 & dcmp_table[i].mask)
            dwCount++;

        // Clear this flag from temporary variable.
        fDecompressions2 &= ~dcmp_table[i].mask;
    }

    // Check if there is some method unhandled
    // (E.g. compressed by future versions)
    if(fDecompressions2 != 0) {
        return 0;
	}

    // If there is more than only one compression, we have to allocate extra buffer
    if(dwCount >= 2) pbTempBuff = (uint8_t*)malloc(dwOutLength);

    // Apply all decompressions
    for(i = 0, dwCount = 0; i < dwEntries; i++)
    {
        // If not used this kind of compression, skip the loop
        if(fDecompressions1 & dcmp_table[i].mask)
        {
            // If odd case, use target buffer for output, otherwise use allocated tempbuffer
            pbWorkBuff  = (dwCount++ & 1) ? pbTempBuff : outputBuffer;
            dwOutLength = *ouputBufferLength;

            // Decompress buffer using corresponding function
            dcmp_table[i].Decompress(pbWorkBuff, &dwOutLength, inputBuffer, inputBufferLength);
            if(dwOutLength == 0)
            {
                nResult = 0;
                break;
            }

            // Move output length to src length for next compression
            inputBufferLength = dwOutLength;
            inputBuffer = pbWorkBuff;
        }
    }

    // If output buffer is not the same like target buffer, we have to copy data
    if(nResult != 0)
    {
        if(pbWorkBuff != outputBuffer)
            memcpy(outputBuffer, pbWorkBuff, dwOutLength);
        
    }

    // Delete temporary buffer, if necessary
    if(pbTempBuff != NULL) free(pbTempBuff);
	
    *ouputBufferLength = dwOutLength;
    return nResult;
}
