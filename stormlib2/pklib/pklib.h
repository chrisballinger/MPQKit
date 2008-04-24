/*****************************************************************************/
/* pklib.h                                Copyright (c) Ladislav Zezula 2003 */
/*---------------------------------------------------------------------------*/
/* Header file for PKWARE Data Compression Library                           */
/*---------------------------------------------------------------------------*/
/*   Date    Ver   Who  Comment                                              */
/* --------  ----  ---  -------                                              */
/* 31.03.03  1.00  Lad  The first version of pkware.h                        */
/*****************************************************************************/

#ifndef __PKLIB_H__
#define __PKLIB_H__

#include <stdint.h>

#ifdef __cplusplus
   extern "C" {
#endif

//-----------------------------------------------------------------------------
// Defines

#define CMP_BINARY             0        // Binary compression
#define CMP_ASCII              1        // Ascii compression

#define CMP_NO_ERROR           0
#define CMP_INVALID_DICTSIZE   1
#define CMP_INVALID_MODE       2
#define CMP_BAD_DATA           3
#define CMP_ABORT              4

//-----------------------------------------------------------------------------
// Internal structures

// Compression structure
typedef struct
{
    uint32_t   offs0000;            // 0000 : 
    uint32_t   out_bytes;           // 0004 : # bytes available in out_buff            
    uint32_t   out_bits;            // 0008 : # of bits available in the last out byte
    uint32_t   dsize_bits;          // 000C : Dict size : 4=0x400, 5=0x800, 6=0x1000
    uint32_t   dsize_mask;          // 0010 : Dict size : 0x0F=0x400, 0x1F=0x800, 0x3F=0x1000
    uint32_t   ctype;               // 0014 : Compression type (Ascii or binary)
    uint32_t   dsize_bytes;         // 0018 : Dictionary size in bytes
    uint8_t    dist_bits[0x40];     // 001C : Distance bits
    uint8_t    dist_codes[0x40];    // 005C : Distance codes
    uint8_t    nChBits[0x306];      // 009C : 
    uint16_t   nChCodes[0x306];     // 03A2 : 
    uint16_t   offs09AE;            // 09AE : 

    void     * param;               // 09B0 : User parameter
    uint32_t   (*read_buf)(uint8_t* buf, uint32_t* size, void* param);  // 9B4
    void       (*write_buf)(uint8_t* buf, uint32_t* size, void* param); // 9B8

    uint16_t   offs09BC[0x204];     // 09BC :
    uint32_t   offs0DC4;            // 0DC4 : 
    uint16_t   offs0DC8[0x900];     // 0DC8 :
    uint16_t   offs1FC8;            // 1FC8 : 
    uint8_t    out_buff[0x802];     // 1FCA : Output (compressed) data
    uint8_t    work_buff[0x2204];   // 27CC : Work buffer
                                    //  + DICT_OFFSET  => Dictionary
                                    //  + UNCMP_OFFSET => Uncompressed data
    uint16_t   offs49D0[0x2000];    // 49D0 : 
} TCmpStruct;

#define CMP_BUFFER_SIZE  sizeof(TCmpStruct) // Size of compression buffer


// Decompression structure
typedef struct
{
    uint32_t      offs0000;             // 0000
    uint32_t      ctype;                // 0004 - Compression type (CMP_BINARY or CMP_ASCII)
    uint32_t      outputPos;            // 0008 - Position in output buffer
    uint32_t      dsize_bits;           // 000C - Dict size (4, 5, 6 for 0x400, 0x800, 0x1000)
    uint32_t      dsize_mask;           // 0010 - Dict size bitmask (0x0F, 0x1F, 0x3F for 0x400, 0x800, 0x1000)
    uint32_t      bit_buff;             // 0014 - 16-bit buffer for processing input data
    uint32_t      extra_bits;           // 0018 - Number of extra (above 8) bits in bit buffer
    uint32_t      in_pos;               // 001C - Position in in_buff
    uint32_t      in_bytes;             // 0020 - Number of bytes in input buffer
    void        * param;                // 0024 - Custom parameter
    uint32_t      (*read_buf)(uint8_t* buf, uint32_t* size, void* param); // 0028
    void          (*write_buf)(uint8_t* buf, uint32_t* size, void* param);// 002C
    uint8_t       out_buff[0x2000];     // 0030 - Output circle buffer. Starting position is 0x1000
    uint8_t       offs2030[0x204];      // 2030 - ???
    uint8_t       in_buff[0x800];       // 2234 - Buffer for data to be decompressed
    uint8_t       position1[0x100];     // 2A34 - Positions in buffers
    uint8_t       position2[0x100];     // 2B34 - Positions in buffers
    uint8_t       offs2C34[0x100];      // 2C34 - Buffer for 
    uint8_t       offs2D34[0x100];      // 2D34 - Buffer for 
    uint8_t       offs2E34[0x80];       // 2EB4 - Buffer for 
    uint8_t       offs2EB4[0x100];      // 2EB4 - Buffer for 
    uint8_t       ChBitsAsc[0x100];     // 2FB4 - Buffer for 
    uint8_t       DistBits[0x40];       // 30B4 - Numbers of bytes to skip copied block length
    uint8_t       LenBits[0x10];        // 30F4 - Numbers of bits for skip copied block length
    uint8_t       ExLenBits[0x10];      // 3104 - Number of valid bits for copied block
    uint16_t      LenBase[0x10];        // 3114 - Buffer for 
} TDcmpStruct;

#define EXP_BUFFER_SIZE    sizeof(TDcmpStruct)  // Size of decompress buffer

//-----------------------------------------------------------------------------
// Public functions

int pk_implode(
   uint32_t     (*read_buf)(uint8_t* buf, uint32_t* size, void* param),
   void         (*write_buf)(uint8_t* buf, uint32_t* size, void* param),
   uint8_t      *work_buf,
   void         *param,
   uint32_t     *type,
   uint32_t     *dsize);

int pk_explode(
   uint32_t     (*read_buf)(uint8_t* buf, uint32_t* size, void* param),
   void         (*write_buf)(uint8_t* buf, uint32_t* size, void* param),
   uint8_t      *work_buf,
   void         *param);

uint32_t pk_crc32(uint8_t* buffer, uint32_t size, uint32_t crc);

#ifdef __cplusplus
   }                         // End of 'extern "C"' declaration
#endif

#endif // __PKLIB_H__
