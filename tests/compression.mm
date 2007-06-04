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

typedef struct {
    char * pInBuff;                     // Pointer to input data buffer
    int    nInPos;                      // Current offset in input data buffer
    int    nInBytes;                    // Number of bytes in the input buffer
    char * pOutBuff;                    // Pointer to output data buffer
    int    nOutPos;                     // Position in the output buffer
    int    nMaxOut;                     // Maximum number of bytes in the output buffer
} TDataInfo;

static unsigned int pkware_read(char *buf, unsigned int *size, void *param) {
    TDataInfo *pInfo = (TDataInfo *)param;
    unsigned int nMaxAvail = (pInfo->nInBytes - pInfo->nInPos);
    unsigned int nToRead = *size;
    if (nToRead > nMaxAvail) nToRead = nMaxAvail;
    memcpy(buf, pInfo->pInBuff + pInfo->nInPos, nToRead);
    pInfo->nInPos += nToRead;
    return nToRead;
}

static void pkware_write(char *buf, unsigned int *size, void *param) {
    TDataInfo * pInfo = (TDataInfo *)param;
    unsigned int nMaxWrite = (pInfo->nMaxOut - pInfo->nOutPos);
    unsigned int nToWrite = *size;
    if (nToWrite > nMaxWrite) nToWrite = nMaxWrite;
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
    TDataInfo ct = {(char *)random_buffer, 0, 0x1000, (char *)compression_buffer, 0, 0x2000};
    char cbuf[CMP_BUFFER_SIZE];
    unsigned int ctype = CMP_BINARY;
    unsigned int dict_size = 0x1000;
    pk_implode(pkware_read, pkware_write, cbuf, &ct, &ctype, &dict_size);
    
    TDataInfo dt = {(char *)compression_buffer, 0, ct.nOutPos, (char *)decompression_buffer, 0, 0x2000};
    char dbuf[EXP_BUFFER_SIZE];
    pk_explode(pkware_read, pkware_write, dbuf, &dt);
    
    STAssertEquals(dt.nOutPos, ct.nInBytes, @"decompressed buffer size does not match input buffer size");
    STAssertFalse(memcmp(decompression_buffer, random_buffer, 0x1000), @"decompressed buffer does not match input buffer");
}

- (void)testHuffmanInternal {
    THuffmannTree *ht = THuffmannTree::AllocateTree();
    TOutputStream os;
    
    os.pbOutBuffer = (unsigned char *)compression_buffer;
    os.dwOutSize   = 0x2000;
    os.pbOutPos    = (unsigned char *)compression_buffer;
    os.dwBitBuff   = 0;
    os.nBits       = 0;

    ht->InitTree(true);
    unsigned int compressed_size = ht->DoCompression(&os, (unsigned char *)random_buffer, 0x1000, 0);
    delete ht;
    
    ht = THuffmannTree::AllocateTree();
    TInputStream is((uint8_t*)compression_buffer, compressed_size);
    ht->InitTree(false);
    unsigned int decompressed_size = ht->DoDecompression((unsigned char *)decompression_buffer, 0x2000, &is);
    delete ht;
    
    STAssertEquals(decompressed_size, (unsigned int)0x1000, @"decompressed buffer size does not match input buffer size");
    STAssertFalse(memcmp(decompression_buffer, random_buffer, 0x1000), @"decompressed buffer does not match input buffer");
}

@end
