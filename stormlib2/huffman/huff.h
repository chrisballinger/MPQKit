/*****************************************************************************/
/* huffman.h                              Copyright (c) Ladislav Zezula 2003 */
/*---------------------------------------------------------------------------*/
/* Description :                                                             */
/*---------------------------------------------------------------------------*/
/*   Date    Ver   Who  Comment                                              */
/* --------  ----  ---  -------                                              */
/* xx.xx.xx  1.00  Lad  The first version of huffman.h                       */
/* 03.05.03  2.00  Lad  Added compression                                    */
/* 08.12.03  2.01  Dan  High-memory handling (> 0x80000000)                  */
/*****************************************************************************/
 
#ifndef __HUFFMAN_H__
#define __HUFFMAN_H__

#include <unistd.h>
#include <stdint.h>
 
// Input stream for Huffmann decompression
class TInputStream {
public:
    TInputStream(uint8_t *data, uint32_t data_size) {
        this->buffer = data;
        this->buffer_bit_size = ((int64_t)data_size) << 3;
        
        this->bit_bucket = 0;
        this->bit_count = 0;
    }
    
    uint32_t GetBit();
    uint32_t Get8Bits();
    
    uint32_t Peek7Bits();
    
    void ConsumeBits(uint32_t count);

private:
    uint8_t *buffer;
    int64_t buffer_bit_size;
    
    uint32_t bit_bucket;
    uint32_t bit_count;
};
 
// Output stream for Huffmann compression
class TOutputStream {
public:
    void PutBits(uint32_t dwBuff, uint32_t nPutBits);

    uint8_t *pbOutBuffer;                   // 00 - Output buffer
    uint32_t dwOutSize;                     // 04 - Size of output buffer
    uint8_t *pbOutPos;                      // 08 - Current output position
    uint32_t dwBitBuff;                     // 0C - Bit buffer
    uint32_t nBits;                         // 10 - Number of bits in the bit buffer
};
 
// Huffmann tree item (?)
struct THTreeItem {
public:
    THTreeItem * Call1501DB70(THTreeItem *pLast);
    THTreeItem * GetPrevItem(intptr_t value);
    void         ClearItemLinks();
    void         RemoveItem();
 
    THTreeItem *next;                       // 00 - Pointer to next THTreeItem
    THTreeItem *prev;                       // 04 - Pointer to prev THTreeItem (< 0 if none)
    uint32_t dcmpByte;                      // 08 - Index of this item in item pointer array, decompressed byte value
    uint32_t byteValue;                     // 0C - Some byte value
    THTreeItem *parent;                     // 10 - Pointer to parent THTreeItem (NULL if none)
    THTreeItem *child;                      // 14 - Pointer to child  THTreeItem
    
    intptr_t addr_multiplier;               // 1 or -1, determined by the address of the parent tree
};
 
// Structure used for quick decompress. The 'bitCount' contains number of bits
// and byte value contains result decompressed byte value.
// After each walk through Huffman tree are filled all entries which are
// multiplies of number of bits loaded from input stream. These entries
// contain number of bits and result value. At the next 7 bits is tested this
// structure first. If corresponding entry found, decompression routine will
// not walk through Huffman tree and directly stores output byte to output stream.
struct TQDecompress {
    uint32_t offs00;                        // 00 - 1 if resolved
    uint32_t nBits;                         // 04 - Bit count
    union
    {
        uintptr_t dcmpByte;                 // 08 - Byte value for decompress (if bitCount <= 7)
        THTreeItem *pItem;                  // 08 - THTreeItem (if number of bits is greater than 7
    };
};
 
// Structure for Huffman tree (Size 0x3674 bytes). Because I'm not expert
// for the decompression, I do not know actually if the class is really a Hufmann
// tree. If someone knows the decompression details, please let me know
class THuffmannTree {
private:
    THuffmannTree();

public:
    static THuffmannTree * AllocateTree();

    void InitTree(bool bCompression);
    
    uint32_t DoCompression(TOutputStream *os, uint8_t *pbInBuffer, int32_t nInLength, int32_t nCmpType);
    uint32_t DoDecompression(uint8_t *pbOutBuffer, uint32_t dwOutLength, TInputStream *is);

private:
    void BuildTree(uint32_t nCmpType);
 
    THTreeItem * Call1500E740(uint32_t nValue);
    void Call1500E820(THTreeItem *pItem);
 
    uint32_t bIsCmp0;                       // 0000 - 1 if compression type 0
    uint32_t offs0004;                      // 0004 - Some flag
    THTreeItem items0008[0x203];            // 0008 - HTree items
 
    //- Sometimes used as HTree item -----------
    THTreeItem *pItem3050;                  // 3050 - Always NULL (?)
    THTreeItem *pItem3054;                  // 3054 - Pointer to Huffman tree item
    THTreeItem *pItem3058;                  // 3058 - Pointer to Huffman tree item (< 0 if invalid)
 
    //- Sometimes used as HTree item -----------
    THTreeItem *pItem305C;                  // 305C - Usually NULL
    THTreeItem *pFirst;                     // 3060 - Pointer to top (first) Huffman tree item
    THTreeItem *pLast;                      // 3064 - Pointer to bottom (last) Huffman tree item (< 0 if invalid)
    uint32_t nItems;                        // 3068 - Number of used HTree items
 
    //-------------------------------------------
    THTreeItem *items306C[0x102];           // 306C - THTreeItem pointer array
    TQDecompress qd3474[0x80];              // 3474 - Array for quick decompression
    
    intptr_t addr_multiplier;               // 1 or -1, determined by the address of the parent tree
 
    static uint8_t Table1502A630[];         // Some table
};
 
#endif // __HUFFMAN_H__
