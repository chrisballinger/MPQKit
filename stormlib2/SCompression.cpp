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
    uint8_t* pInBuff;                   // Pointer to input data buffer
    uint32_t nInPos;                    // Current offset in input data buffer
    uint32_t nInBytes;                  // Number of bytes in the input buffer
    uint8_t* pOutBuff;                  // Pointer to output data buffer
    uint32_t nOutPos;                   // Position in the output buffer
    uint32_t nMaxOut;                   // Maximum number of bytes in the output buffer
} TDataInfo;

// Table of compression functions
typedef int (*COMPRESS)(void *, uint32_t *, void *, uint32_t, int32_t, int32_t);
typedef struct  
{
    MPQCompressorFlag mask;             // Compression mask
    COMPRESS Compress;                  // Compression function
} TCompressTable;

// Table of decompression functions
typedef int (*DECOMPRESS)(void *, uint32_t *, void *, uint32_t);
typedef struct
{
    MPQCompressorFlag   mask;           // Decompression bit
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

static uint32_t ReadInputData(uint8_t* buf, uint32_t* size, void* param)
{
    TDataInfo* pInfo = (TDataInfo*)param;
    uint32_t nMaxAvail = (pInfo->nInBytes - pInfo->nInPos);
    uint32_t nToRead = *size;

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

static void WriteOutputData(uint8_t* buf, uint32_t* size, void* param)
{
    TDataInfo* pInfo = (TDataInfo*)param;
    uint32_t nMaxWrite = (pInfo->nMaxOut - pInfo->nOutPos);
    uint32_t nToWrite = *size;

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

static int Compress_adpcm_mono(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength, int32_t compressionType, int32_t compressionLevel)
{
    *outBufferLength = CompressWave((unsigned char*)outBuffer, *outBufferLength, (short*)inBuffer, inBufferLength, 1, compressionLevel);
    return 1;
}

static int Decompress_adpcm_mono(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength)
{
    *outBufferLength = DecompressWave((int16_t*)outBuffer, *outBufferLength, (uint8_t*)inBuffer, inBufferLength, 1);
    return 1;
}

static int Compress_adpcm_stereo(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength, int32_t compressionType, int32_t compressionLevel)
{
    *outBufferLength = CompressWave((unsigned char*)outBuffer, *outBufferLength, (short*)inBuffer, inBufferLength, 2, compressionLevel);
    return 1;
}

static int Decompress_adpcm_stereo(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength) {
    *outBufferLength = DecompressWave((int16_t*)outBuffer, *outBufferLength, (uint8_t*)inBuffer, inBufferLength, 2);
    return 1;
}

/*****************************************************************************/
/*                                                                           */
/*  The "01" (de)compression is the Huffman (?) (de)compression              */
/*                                                                           */
/*****************************************************************************/

static int Compress_huff(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength, int32_t compressionType, int32_t compressionLevel)
{
    THuffmanTree* ht = THuffmanTree::AllocateTree();
    TOutputStream os;

    // Initialize output stream
    os.pbOutBuffer = (uint8_t*)outBuffer;
    os.dwOutSize   = *outBufferLength;
    os.pbOutPos    = (uint8_t*)outBuffer;
    os.dwBitBuff   = 0;
    os.nBits       = 0;

    // Initialize the Huffman tree for compression
    ht->InitTree(true);

    *outBufferLength = ht->DoCompression(&os, (uint8_t*)inBuffer, inBufferLength, compressionType);

    delete ht;
    return 1;
}

static int Decompress_huff(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength)
{
    THuffmanTree* ht = THuffmanTree::AllocateTree();
    TInputStream is((uint8_t*)inBuffer, inBufferLength);

    // Initialize the Huffman tree for decompression
    ht->InitTree(false);

    *outBufferLength = ht->DoDecompression((uint8_t*)outBuffer, *outBufferLength, &is);
    
    delete ht;
    return 1;
}

/*****************************************************************************/
/*                                                                           */
/*  The "02" (de)compression is the ZLIB (de)compression                     */
/*                                                                           */
/*****************************************************************************/

static int Compress_zlib(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength, int32_t compressionType, int32_t compressionLevel)
{
    z_stream z;
    int nResult;
    
    // Fill the stream structure for zlib
    z.next_in   = (Bytef*)inBuffer;
    z.avail_in  = inBufferLength;
    z.total_in  = inBufferLength;
    z.next_out  = (Bytef*)outBuffer;
    z.avail_out = *outBufferLength;
    z.total_out = 0;
    z.zalloc    = 0;
    z.zfree     = 0;
    z.opaque    = 0;
    
    // Initialize the output length
    *outBufferLength = 0;
    
    // Initialize zlib for compression
    nResult = deflateInit(&z, compressionLevel);
    if (nResult != Z_OK) return 0;
    
    // Call zlib to compress the data
    nResult = deflate(&z, Z_FINISH);
    
    // Finalize the compression
    deflateEnd(&z);
    
	// Explicit cast should be OK here, SCompression cannot handle input sizes beyond uint32_t
    if (nResult == Z_STREAM_END) *outBufferLength = (uint32_t)z.total_out;
    return (nResult == Z_STREAM_END) ? 1 : 0;
}

static int Decompress_zlib(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength)
{
    z_stream z;
    int nResult;
    
    // Fill the stream structure for zlib
    z.next_in   = (Bytef*)inBuffer;
    z.avail_in  = inBufferLength;
    z.total_in  = inBufferLength;
    z.next_out  = (Bytef*)outBuffer;
    z.avail_out = *outBufferLength;
    z.total_out = 0;
    z.zalloc    = 0;
    z.zfree     = 0;
    z.opaque    = 0;
    
    // Initialize the output length
    *outBufferLength = 0;
    
    // Initialize zlib for decompression
    nResult = inflateInit(&z);
    if (nResult != Z_OK) return 0;
    
    // Call zlib to decompress the data
    nResult = inflate(&z, Z_FINISH);
    
    // Finalize the compression
    inflateEnd(&z);
    
	// Explicit cast should be OK here, SCompression cannot handle input sizes beyond uint32_t
    if (nResult == Z_STREAM_END) *outBufferLength = (uint32_t)z.total_out;
    return (nResult == Z_STREAM_END) ? 1 : 0;
}

/*****************************************************************************/
/*                                                                           */
/*  The "08" (de)compression is the Pkware DCL (de)compression               */
/*                                                                           */
/*****************************************************************************/

static int Compress_pklib(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength, int32_t compressionType, int32_t compressionLevel)
{
    TDataInfo Info;                     // Data information
    uint8_t work_buf[CMP_BUFFER_SIZE];  // Pklib's work buffer
    uint32_t dict_size;                 // Dictionary size
    uint32_t ctype;                     // Compression type

    // Fill data information structure
    Info.pInBuff  = (uint8_t*)inBuffer;
    Info.nInPos   = 0;
    Info.nInBytes = inBufferLength;
    Info.pOutBuff = (uint8_t*)outBuffer;
    Info.nOutPos  = 0;
    Info.nMaxOut  = *outBufferLength;

    // Set the compression type and dictionary size
    ctype = (compressionType == 2) ? CMP_ASCII : CMP_BINARY;
    if (inBufferLength < 0x600) dict_size = 0x400;
    else if(0x600 <= inBufferLength && inBufferLength < 0xC00) dict_size = 0x800;
    else dict_size = 0x1000;

    // Do the compression
    pk_implode(ReadInputData, WriteOutputData, work_buf, &Info, &ctype, &dict_size);
    *outBufferLength = Info.nOutPos;
    return 1;
}

int Decompress_pklib(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength)
{
    TDataInfo Info;                     // Data information
    uint8_t work_buf[EXP_BUFFER_SIZE];  // Pklib's work buffer

    // Fill data information structure
    Info.pInBuff  = (uint8_t*)inBuffer;
    Info.nInPos   = 0;
    Info.nInBytes = inBufferLength;
    Info.pOutBuff = (uint8_t*)outBuffer;
    Info.nOutPos  = 0;
    Info.nMaxOut  = *outBufferLength;

    // Do the decompression
    pk_explode(ReadInputData, WriteOutputData, work_buf, &Info);
    
    // Fix : If PKLIB is unable to decompress the data, they are uncompressed
    if (Info.nOutPos == 0) {
        Info.nOutPos = min(*outBufferLength, inBufferLength);
        memcpy(outBuffer, inBuffer, Info.nOutPos);
    }

    *outBufferLength = Info.nOutPos;
	return 1;
}

/*****************************************************************************/
/*                                                                           */
/*  The "10" (de)compression is the bzip2 (de)compression                     */
/*                                                                           */
/*****************************************************************************/

static int Compress_bz2(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength, int32_t compressionType, int32_t compressionLevel)
{
    bz_stream s;
    int nResult;
	
    // Fill the stream structure for bz2
    s.next_in   = (char*)inBuffer;
    s.avail_in  = inBufferLength;
    s.next_out  = (char*)outBuffer;
    s.avail_out = *outBufferLength;
	s.bzalloc   = 0;
	s.bzfree    = 0;
	s.opaque    = 0;
	
	// Initialize the output length
	*outBufferLength = 0;
	
	// Init bz2 for compression
	nResult = BZ2_bzCompressInit(&s, compressionLevel, 0, 0);
	if (nResult != BZ_OK) return 0;
	
	// Call bz2 to compress the data
    do {
        nResult = BZ2_bzCompress(&s, (s.avail_in != 0) ? BZ_RUN : BZ_FINISH);
    } while (nResult == BZ_RUN_OK || nResult == BZ_FLUSH_OK || nResult == BZ_FINISH_OK);
    
	// Finalize the compression
	BZ2_bzCompressEnd(&s);
	
    if (nResult == BZ_STREAM_END) *outBufferLength = s.total_out_lo32;
    return (nResult == BZ_STREAM_END) ? 1 : 0;
}

static int Decompress_bz2(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength) {
	bz_stream s;	// Stream information for bz2
    int nResult;
	
    // Fill the stream structure for bz2
    s.next_in   = (char*)inBuffer;
    s.avail_in  = inBufferLength;
    s.next_out  = (char*)outBuffer;
    s.avail_out = *outBufferLength;
	s.bzalloc   = 0;
	s.bzfree    = 0;
	s.opaque    = 0;
	
    // Initialize the output length
	*outBufferLength = 0;
    
	// Init bz2 for decompression
	nResult = BZ2_bzDecompressInit(&s, 0, 0);
	if (nResult != BZ_OK) return 0;

	// Call bz2 to decompress the data
    do {
        nResult = BZ2_bzDecompress(&s);
    } while (nResult == BZ_OK);
	
    // Finalize the decompression
    BZ2_bzDecompressEnd(&s);
    
    if (nResult == BZ_STREAM_END) *outBufferLength = s.total_out_lo32;
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
static TCompressTable cmp_table[] =
{
    {MPQMonoADPCMCompression, Compress_adpcm_mono},         // Mono ADPCM
    {MPQStereoADPCMCompression, Compress_adpcm_stereo},     // Stereo ADPCM
    {MPQHuffmanTreeCompression, Compress_huff},             // Huffman
    {MPQZLIBCompression, Compress_zlib},                    // zlib
    {MPQPKWARECompression, Compress_pklib},                 // Pkware Data Compression Library
    {MPQBZIP2Compression, Compress_bz2}                     // bzip2
};

int SCompCompress(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength, MPQCompressorFlag compressors, int32_t compressionType, int32_t compressionLevel) {
    void* pbTempBuff = 0;                   // Temporary storage for decompressed data
    void* pbOutput;                         // Current output buffer
    void* pbInput;                          // Current input buffer
    uint8_t uCompressions2;
    uint32_t dwCompressCount = 0;
    uint32_t dwDoneCount = 0;
    uint32_t dwOutSize = 0;
    uint32_t dwInSize;
    // Explicit 32-bit cast should not be a problem here, there will not be more entries than the range of 32-bit integers
	uint32_t dwEntries = (uint32_t)(sizeof(cmp_table) / sizeof(TCompressTable));
    int nResult = 1;
    uint32_t i;       

    // Check for valid parameters
    if (!outBufferLength || *outBufferLength < inBufferLength || !outBuffer || !inBuffer) return 0;
	
	// If input is 0 bytes, there's nothing to do
	if (inBufferLength == 0) {
		*outBufferLength = 0;
		return 1;
	}

    // Count the compressions
    for(i = 0, uCompressions2 = compressors; i < dwEntries; i++)
    {
        if(compressors & cmp_table[i].mask)
            dwCompressCount++;

        uCompressions2 &= ~cmp_table[i].mask;
    }

    // If a compression remains (e.g. an unknown compressor), do nothing
    if(uCompressions2 != 0) {
        *outBufferLength = 0;
		return 0;
	}

    // If more that one compression, allocate intermediate buffer
    if(dwCompressCount > 1) pbTempBuff = malloc(*outBufferLength);

    // Perform the compressions
    pbInput = inBuffer;
    dwInSize = inBufferLength;
    for(i = 0, uCompressions2 = compressors; i < dwEntries; i++)
    {
        if(uCompressions2 & cmp_table[i].mask)
        {
            // Set the right output buffer 
            dwCompressCount--;
            pbOutput = (dwCompressCount & 1) ? pbTempBuff : outBuffer;

            // Perform the partial compression
            dwOutSize = *outBufferLength - 1;

            cmp_table[i].Compress((uint8_t*)pbOutput + 1, &dwOutSize, pbInput, dwInSize, compressionType, compressionLevel);
            if(dwOutSize == 0)
            {
                *outBufferLength = 0;
                nResult = 0;
                break;
            }

            // If the compression failed, copy the block instead
            if(dwOutSize >= dwInSize - 1)
            {
                if(dwDoneCount > 0)
                    pbOutput = (uint8_t*)pbOutput + 1;

                memcpy(pbOutput, pbInput, dwInSize);
                pbInput = pbOutput;
                compressors &= ~cmp_table[i].mask;
                dwOutSize = dwInSize;
            }
            else
            {
                pbInput = (uint8_t*)pbOutput + 1;
                dwInSize = dwOutSize;
                dwDoneCount++;
            }
        }
    }

    // Finalize the compression
    if(nResult != 0)
    {
        // Did we actually use the output of a compressor and have enough space in the output buffer to store the final compressed data and the compressor BOM
        if(compressors && (dwInSize + 1) <= *outBufferLength)
        {
            *((uint8_t*)outBuffer) = compressors;
            *outBufferLength = dwInSize + 1;
        }
        else
        {
            memmove(outBuffer, inBuffer, dwInSize);
            *outBufferLength = dwInSize;
        }
    }

    // Cleanup and return
    if(pbTempBuff != 0) free(pbTempBuff);
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
    {MPQBZIP2Compression, Decompress_bz2},                      // bzip2
    {MPQPKWARECompression, Decompress_pklib},                   // Pkware Data Compression Library
    {MPQZLIBCompression, Decompress_zlib},                      // zlib
    {MPQHuffmanTreeCompression, Decompress_huff},               // Huffman
    {MPQStereoADPCMCompression, Decompress_adpcm_stereo},       // Stereo ADPCM
    {MPQMonoADPCMCompression, Decompress_adpcm_mono}            // Mono ADPCM
};

int SCompDecompress(void* outBuffer, uint32_t* outBufferLength, void* inBuffer, uint32_t inBufferLength) {
    void* pbTempBuff = 0;                           // Temporary storage for decompressed data
    void* pbWorkBuff = 0;                           // Where to store decompressed data
    uint32_t dwOutLength = *outBufferLength;        // For storage number of output bytes
    uint8_t fDecompressions1;                       // Decompressions applied to the block
    uint8_t fDecompressions2;                       // Just another copy of decompressions applied to the block
    int32_t dwCount = 0;                            // Counter for every use
    // Explicit 32-bit cast should not be a problem here, there will not be more entries than the range of 32-bit integers
	uint32_t dwEntries = (uint32_t)(sizeof(dcmp_table) / sizeof(TDecompressTable));
    int nResult = 1;
    uint32_t i;
    
    // Check for valid parameters
    if (!outBufferLength || *outBufferLength < inBufferLength || !outBuffer || !inBuffer) return 0;
    
    // If the input length is the same as output, do nothing
    if(inBufferLength == dwOutLength)
    {
        if(inBuffer == outBuffer)
            return 1;

        memcpy(outBuffer, inBuffer, inBufferLength);
        *outBufferLength = inBufferLength;
        return 1;
    }
	
	// If input is 0 bytes, there's nothing to do
	if (inBufferLength == 0) {
		*outBufferLength = 0;
		return 1;
	}
    
    // Get applied compression types and decrement data length
    fDecompressions1 = fDecompressions2 = *((uint8_t*)inBuffer);
    inBuffer = (void*)((uint8_t*)inBuffer + 1);
    inBufferLength--;
    
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
    if(dwCount > 1) pbTempBuff = malloc(dwOutLength);

    // Apply all decompressions
    for(i = 0, dwCount = 0; i < dwEntries; i++)
    {
        // If not used this kind of compression, skip the loop
        if(fDecompressions1 & dcmp_table[i].mask)
        {
            // If odd case, use target buffer for output, otherwise use allocated tempbuffer
            pbWorkBuff  = (dwCount++ & 1) ? pbTempBuff : outBuffer;
            dwOutLength = *outBufferLength;

            // Decompress buffer using corresponding function
            dcmp_table[i].Decompress(pbWorkBuff, &dwOutLength, inBuffer, inBufferLength);
            if(dwOutLength == 0)
            {
                nResult = 0;
                break;
            }

            // Move output length to src length for next compression
            inBufferLength = dwOutLength;
            inBuffer = pbWorkBuff;
        }
    }

    // If output buffer is not the same like target buffer, we have to copy data
    if(nResult != 0)
    {
        if(pbWorkBuff != outBuffer)
            memcpy(outBuffer, pbWorkBuff, dwOutLength);
        
    }

    // Delete temporary buffer, if necessary
    if(pbTempBuff != 0) free(pbTempBuff);
	
    *outBufferLength = dwOutLength;
    return nResult;
}
