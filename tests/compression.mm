//
//  compression.m
//  MPQKit
//
//  Created by Jean-François Roy on 02/06/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#import <unistd.h>

#import <MPQKit/pklib.h>
#import <MPQKit/huff.h>

#import "compression.h"

typedef struct
{
    uint8_t *pInBuff;                   // Pointer to input data buffer
    uint32_t nInPos;                    // Current offset in input data buffer
    uint32_t nInBytes;                  // Number of bytes in the input buffer
    uint8_t *pOutBuff;                  // Pointer to output data buffer
    uint32_t nOutPos;                   // Position in the output buffer
    uint32_t nMaxOut;                   // Maximum number of bytes in the output buffer
} TDataInfo;

static uint32_t ReadInputData(uint8_t *buf, uint32_t *size, void *param)
{
    TDataInfo *pInfo = (TDataInfo *)param;
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

static void WriteOutputData(uint8_t *buf, uint32_t *size, void *param)
{
    TDataInfo *pInfo = (TDataInfo *)param;
    uint32_t nMaxWrite = (pInfo->nMaxOut - pInfo->nOutPos);
    uint32_t nToWrite = *size;

    // Check the case when not enough space in the output buffer
    if(nToWrite > nMaxWrite)
        nToWrite = nMaxWrite;

    // Write output data and increments offsets
    memcpy(pInfo->pOutBuff + pInfo->nOutPos, buf, nToWrite);
    pInfo->nOutPos += nToWrite;
}

@implementation compression

- (void)setUp {
    random_buffer = malloc(0x2000);
    compression_buffer = malloc(0x2000);
    decompression_buffer = malloc(0x2000);
    
    int rfd = open("/dev/urandom", O_RDONLY, 0);
    if (rfd == -1) {
        perror("opening /dev/urandom failed!");
        abort();
    }
    
    ssize_t bread = read(rfd, random_buffer, 0x1000);
    if (bread != 0x1000) {
        perror("reading /dev/urandom failed!");
        abort();
    }
    
    close(rfd);
}
 
- (void)tearDown {
    free(random_buffer);
    free(compression_buffer);
    free(decompression_buffer);
}

- (void)testPKWAREInternal {
    TDataInfo ct = {(uint8_t *)random_buffer, 0, 0x1000, (uint8_t *)compression_buffer, 0, 0x2000};
    uint8_t cbuf[CMP_BUFFER_SIZE];
    uint32_t ctype = CMP_BINARY;
    uint32_t dict_size = 0x1000;
    pk_implode(ReadInputData, WriteOutputData, cbuf, &ct, &ctype, &dict_size);
    
    TDataInfo dt = {(uint8_t *)compression_buffer, 0, ct.nOutPos, (uint8_t *)decompression_buffer, 0, 0x2000};
    uint8_t dbuf[EXP_BUFFER_SIZE];
    pk_explode(ReadInputData, WriteOutputData, dbuf, &dt);
    
    STAssertEquals(dt.nOutPos, ct.nInBytes, @"decompressed buffer size does not match input buffer size");
    STAssertFalse(memcmp(decompression_buffer, random_buffer, 0x1000), @"decompressed buffer does not match input buffer");
}

- (void)testHuffmanInternal {
    THuffmanTree *ht = THuffmanTree::AllocateTree();
    TOutputStream os;
    
    os.pbOutBuffer = (uint8_t *)compression_buffer;
    os.dwOutSize   = 0x2000;
    os.pbOutPos    = (uint8_t *)compression_buffer;
    os.dwBitBuff   = 0;
    os.nBits       = 0;

    ht->InitTree(true);
    uint32_t compressed_size = ht->DoCompression(&os, (uint8_t *)random_buffer, 0x1000, 0);
    delete ht;
    
    ht = THuffmanTree::AllocateTree();
    TInputStream is((uint8_t*)compression_buffer, compressed_size);
    ht->InitTree(false);
    uint32_t decompressed_size = ht->DoDecompression((uint8_t *)decompression_buffer, 0x2000, &is);
    delete ht;
    
    STAssertEquals(decompressed_size, (uint32_t)0x1000, @"decompressed buffer size does not match input buffer size");
    STAssertFalse(memcmp(decompression_buffer, random_buffer, 0x1000), @"decompressed buffer does not match input buffer");
}

@end
