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
    char * pInBuff;                     // Pointer to input data buffer
    int    nInPos;                      // Current offset in input data buffer
    int    nInBytes;                    // Number of bytes in the input buffer
    char * pOutBuff;                    // Pointer to output data buffer
    int    nOutPos;                     // Position in the output buffer
    int    nMaxOut;                     // Maximum number of bytes in the output buffer
} TDataInfo;

// Table of compression functions
typedef int (*COMPRESS)(char *, int *, char *, int, int *, int);
typedef struct  
{
    unsigned long dwMask;               // Compression mask
    COMPRESS Compress;                  // Compression function
} TCompressTable;

// Table of decompression functions
typedef int32_t (*DECOMPRESS)(uint8_t*, int32_t*, uint8_t*, int32_t);
typedef struct
{
    unsigned long dwMask;               // Decompression bit
    DECOMPRESS    Decompress;           // Decompression function
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

int Compress_wave_mono(char * pbOutBuffer, int * pdwOutLength, char * pbInBuffer, int dwInLength, int * pCmpType, int nCmpLevel)
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
    return 0;
}

int Decompress_wave_mono(uint8_t* pbOutBuffer, int32_t* pdwOutLength, uint8_t* pbInBuffer, int32_t dwInLength) {
    *pdwOutLength = DecompressWave(pbOutBuffer, *pdwOutLength, pbInBuffer, dwInLength, 1);
    return 1;
}

int Compress_wave_stereo(char * pbOutBuffer, int * pdwOutLength, char * pbInBuffer, int dwInLength, int * pCmpType, int nCmpLevel)
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
    return 0;
}

int Decompress_wave_stereo(uint8_t* pbOutBuffer, int32_t* pdwOutLength, uint8_t* pbInBuffer, int32_t dwInLength) {
    *pdwOutLength = DecompressWave(pbOutBuffer, *pdwOutLength, pbInBuffer, dwInLength, 2);
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
    return 0;
}

int Decompress_huff(uint8_t* pbOutBuffer, int32_t* pdwOutLength, uint8_t* pbInBuffer, int32_t dwInLength) {
    THuffmanTree *ht = THuffmanTree::AllocateTree();
    TInputStream is(pbInBuffer, dwInLength);

    // Initialize the Huffman tree for decompression
    ht->InitTree(false);

    *pdwOutLength = ht->DoDecompression((unsigned char *)pbOutBuffer, *pdwOutLength, &is);
    
    delete ht;
    return 0;
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

int Decompress_zlib(uint8_t* pbOutBuffer, int32_t* pdwOutLength, uint8_t* pbInBuffer, int32_t dwInLength) {
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

    // Initialize the decompression structure. Storm.dll uses zlib version 1.1.3
    if((nResult = inflateInit(&z)) == 0)
    {
        // Call zlib to decompress the data
        nResult = inflate(&z, Z_FINISH);
        *pdwOutLength = z.total_out;
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
    return 0;
}

int32_t Decompress_pklib(uint8_t* pbOutBuffer, int32_t* pdwOutLength, uint8_t* pbInBuffer, int32_t dwInLength) {
    TDataInfo Info;                     // Data information
    char work_buf[EXP_BUFFER_SIZE];     // Pklib's work buffer

    // Fill data information structure
    Info.pInBuff  = (char*)pbInBuffer;
    Info.nInPos   = 0;
    Info.nInBytes = dwInLength;
    Info.pOutBuff = (char*)pbOutBuffer;
    Info.nOutPos  = 0;
    Info.nMaxOut  = *pdwOutLength;

    // Do the decompression
    pk_explode(ReadInputData, WriteOutputData, work_buf, &Info);
    
    // Fix : If PKLIB is unable to decompress the data, they are uncompressed
    if(Info.nOutPos == 0)
    {
        Info.nOutPos = min(*pdwOutLength, dwInLength);
        memcpy(pbOutBuffer, pbInBuffer, Info.nOutPos);
    }

    *pdwOutLength = Info.nOutPos;
	return 0;
}

/*****************************************************************************/
/*                                                                           */
/*  The "10" (de)compression is the bzip2 (de)compression                     */
/*                                                                           */
/*****************************************************************************/

int Compress_bz2(char * pbOutBuffer, int * pdwOutLength, char * pbInBuffer, int dwInLength, int * /* pCmpType */, int nCmpLevel)
{
    bz_stream s;                        // Stream information for bz2
    int nResult;
	
	s.bzalloc = NULL;
	s.bzfree = NULL;
	s.opaque = NULL;
	
	// Initialize the output length
	*pdwOutLength = 0;
	
	// init bz2 for compression
	nResult = BZ2_bzCompressInit(&s, nCmpLevel, 0, 0);
	if (nResult != BZ_OK) return nResult;
	
	// Fill the stream structure for bz2
    s.next_in   = pbInBuffer;
    s.avail_in  = (unsigned int)dwInLength;
    s.next_out  = pbOutBuffer;
    s.avail_out = *((unsigned int *)pdwOutLength);
	
	// Call bz2 to compress the data
	while (BZ2_bzCompress(&s, (s.avail_in != 0) ? BZ_RUN : BZ_FINISH) != BZ_STREAM_END);
    
	// Finalize the compression
	BZ2_bzCompressEnd(&s);
	*pdwOutLength = s.total_out_lo32;
	
    return 0;
}

int Decompress_bz2(uint8_t* pbOutBuffer, int32_t* pdwOutLength, uint8_t* pbInBuffer, int32_t dwInLength) {
	bz_stream s;	// Stream information for bz2
    int nResult;
	
	s.bzalloc = NULL;
	s.bzfree = NULL;
	s.opaque = NULL;
	
	// init bz2 for decompression
	nResult = BZ2_bzDecompressInit(&s, 0, 0);
	if(nResult != BZ_OK) {
		return nResult;
	}

    // Fill the stream structure for bz2
    s.next_in   = (char*)pbInBuffer;
    s.avail_in  = (unsigned int)dwInLength;
    s.next_out  = (char*)pbOutBuffer;
    s.avail_out = *((unsigned int *)pdwOutLength);

	// Call bz2 to decompress the data
	while(nResult != BZ_STREAM_END && s.avail_in > 0 && s.next_out > 0) {
		nResult = BZ2_bzDecompress(&s);
	}
	
	*pdwOutLength = s.total_out_lo32;
	nResult = BZ2_bzDecompressEnd(&s);
	
    return nResult;
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
    {0x40, Compress_wave_mono},         // Mono ADPCM
    {0x80, Compress_wave_stereo},       // Stereo ADPCM
    {0x01, Compress_huff},              // Huffman
    {0x02, Compress_zlib},              // zlib
    {0x08, Compress_pklib},             // Pkware Data Compression Library
    {0x10, Compress_bz2}                // bzip2
};

int SCompCompress(char * pbCompressed, int * pdwOutLength, char * pbUncompressed, int dwInLength, int uCompressions, int nCmpType, int nCmpLevel)
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
        if(uCompressions & cmp_table[i].dwMask)
            dwCompressCount++;

        uCompressions2 &= ~cmp_table[i].dwMask;
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
        if(uCompressions2 & cmp_table[i].dwMask)
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
                uCompressions &= ~cmp_table[i].dwMask;
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
    {0x80, Decompress_wave_stereo},     // Stereo ADPCM
    {0x40, Decompress_wave_mono}        // Mono ADPCM
};

int32_t SCompDecompress(uint8_t* pbOutBuffer, int32_t* pdwOutLength, uint8_t* pbInBuffer, int32_t dwInLength) {
    uint8_t *pbTempBuff = NULL;             // Temporary storage for decompressed data
    uint8_t *pbWorkBuff = NULL;             // Where to store decompressed data
    int32_t dwOutLength = *pdwOutLength;    // For storage number of output bytes
    uint32_t fDecompressions1;              // Decompressions applied to the block
    uint32_t fDecompressions2;              // Just another copy of decompressions applied to the block
    int32_t dwCount = 0;                    // Counter for every use
    int32_t dwEntries = (sizeof(dcmp_table) / sizeof(TDecompressTable));
    int32_t nResult = 1;
    int32_t i;       

    // If the input length is the same as output, do nothing.
    if(dwInLength == dwOutLength)
    {
        if(pbInBuffer == pbOutBuffer)
            return 1;

        memcpy(pbOutBuffer, pbInBuffer, dwInLength);
        *pdwOutLength = dwInLength;
        return 1;
    }
    
    // Get applied compression types and decrement data length
    fDecompressions1 = fDecompressions2 = (unsigned char)*pbInBuffer++;              
    dwInLength--;
    
    // Search decompression table type and get all types of compression
    for(i = 0; i < dwEntries; i++)
    {
        // We have to apply this decompression ?
        if(fDecompressions1 & dcmp_table[i].dwMask)
            dwCount++;

        // Clear this flag from temporary variable.
        fDecompressions2 &= ~dcmp_table[i].dwMask;
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
        if(fDecompressions1 & dcmp_table[i].dwMask)
        {
            // If odd case, use target buffer for output, otherwise use allocated tempbuffer
            pbWorkBuff  = (dwCount++ & 1) ? pbTempBuff : pbOutBuffer;
            dwOutLength = *pdwOutLength;

            // Decompress buffer using corresponding function
            dcmp_table[i].Decompress(pbWorkBuff, &dwOutLength, pbInBuffer, dwInLength);
            if(dwOutLength == 0)
            {
                nResult = 0;
                break;
            }

            // Move output length to src length for next compression
            dwInLength = dwOutLength;
            pbInBuffer = pbWorkBuff;
        }
    }

    // If output buffer is not the same like target buffer, we have to copy data
    if(nResult != 0)
    {
        if(pbWorkBuff != pbOutBuffer)
            memcpy(pbOutBuffer, pbInBuffer, dwOutLength);
        
    }

    // Delete temporary buffer, if necessary
    if(pbTempBuff != NULL) free(pbTempBuff);
	
    *pdwOutLength = dwOutLength;
    return nResult;
}
