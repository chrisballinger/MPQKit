/*
 *  MPQCryptography.c
 *  MPQKit
 *
 *  Created by Jean-Francois Roy on Sat Oct 05 2002.
 *  Copyright (c) 2002-2007 MacStorm. All rights reserved.
 *
 */

#include <assert.h>
#include <string.h>
#include <zlib.h>

#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/md5.h>
#include <openssl/obj_mac.h>
#include <openssl/sha.h>

#include "MPQByteOrder.h"
#include "MPQCryptography.h"

#define BUFFER_OFFSET(buffer, bytes) ((uint8_t*)buffer + (bytes))

#if !defined(Boolean)
#define Boolean int
#define FALSE 0
#define TRUE 1
#endif

static Boolean crypt_table_initialized = FALSE;
static uint32_t crypt_table[0x500];
static const uLongf* crc_table;

static void memrev(unsigned char* buf, size_t count) {
    unsigned char* r;
    for (r = buf + count - 1; buf < r; buf++, r--) {
        *buf ^= *r;
        *r   ^= *buf;
        *buf ^= *r;
    }
}

const uint32_t* mpq_get_cryptography_table() {
    assert(crypt_table_initialized);
    return crypt_table;
}

void mpq_init_cryptography() {
    // prepare crypt_table
    uint32_t seed   = 0x00100001;
    uint32_t index1 = 0;
    uint32_t index2 = 0;
    int32_t i;
        
    if (!crypt_table_initialized) {
         crypt_table_initialized = TRUE;
         
         for (index1 = 0; index1 < 0x100; index1++) {
              for (index2 = index1, i = 0; i < 5; i++, index2 += 0x100) {
                    uint32_t temp1, temp2;
        
                    seed  = (seed * 125 + 3) % 0x2AAAAB;
                    temp1 = (seed & 0xFFFF) << 0x10;
        
                    seed  = (seed * 125 + 3) % 0x2AAAAB;
                    temp2 = (seed & 0xFFFF);
        
                    crypt_table[index2] = (temp1 | temp2);
              }
         }
    }
    
    // load up OpenSSL
    OpenSSL_add_all_digests();
    OpenSSL_add_all_algorithms();
    OpenSSL_add_all_ciphers();
    ERR_load_crypto_strings();
	
	crc_table = get_crc_table();
}

void mpq_encrypt(void* data, size_t length, uint32_t key, bool disable_input_swapping) {
    assert(crypt_table_initialized);
    assert(data);
    
    uint32_t* buffer32 = (uint32_t*)data;
    uint32_t seed = 0xEEEEEEEE;
    uint32_t ch;
    
    // round to 4 bytes
    length = length / 4;
    
    // we duplicate the loop to avoid costly branches
    if (disable_input_swapping) {
        while (length-- > 0) {
            seed += crypt_table[0x400 + (key & 0xFF)];
            ch = *buffer32 ^ (key + seed);
            
            key = ((~key << 0x15) + 0x11111111) | (key >> 0x0B);
            seed = *buffer32 + seed + (seed << 5) + 3;
            
			*buffer32++ = MPQSwapInt32HostToLittle(ch);
        }
    } else {
        while (length-- > 0) {
            *buffer32 = MPQSwapInt32LittleToHost(*buffer32);
            
            seed += crypt_table[0x400 + (key & 0xFF)];
            ch = *buffer32 ^ (key + seed);
            
            key = ((~key << 0x15) + 0x11111111) | (key >> 0x0B);
            seed = *buffer32 + seed + (seed << 5) + 3;
            
			*buffer32++ = MPQSwapInt32HostToLittle(ch);
        }
    }
}

void mpq_decrypt(void* data, size_t length, uint32_t key, bool disable_output_swapping) {
    assert(crypt_table_initialized);
    assert(data);
    
    uint32_t* buffer32 = (uint32_t*)data;
    uint32_t seed = 0xEEEEEEEE;
    uint32_t ch;
    
    // round to 4 bytes
    length = length / 4;
    
    if (disable_output_swapping) {
        while (length-- > 0) {
			ch = MPQSwapInt32LittleToHost(*buffer32);
            
            seed += crypt_table[0x400 + (key & 0xFF)];
            ch = ch ^ (key + seed);
            
            key = ((~key << 0x15) + 0x11111111) | (key >> 0x0B);
            seed = ch + seed + (seed << 5) + 3;
            
            *buffer32++ = ch;
        }
        
    } else {
        while (length-- > 0) {
            ch = MPQSwapInt32LittleToHost(*buffer32);
            
            seed += crypt_table[0x400 + (key & 0xFF)];
            ch = ch ^ (key + seed);
            
            key = ((~key << 0x15) + 0x11111111) | (key >> 0x0B);
            seed = ch + seed + (seed << 5) + 3;
            
            *buffer32++ = MPQSwapInt32HostToLittle(ch);
        }
    }
}

uint32_t mpq_hash_cstring(const char* string, uint32_t type) {
    assert(crypt_table_initialized);
    assert(string);
    
    uint32_t seed1 = 0x7FED7FED;
    uint32_t seed2 = 0xEEEEEEEE;
    uint32_t shifted_type = (type << 8);
    uint32_t ch;
    
    while (*string != 0) {
        ch = *string++;
        if (ch > 0x60 && ch < 0x7b) ch -= 0x20;

        seed1 = crypt_table[shifted_type + ch] ^ (seed1 + seed2);
        seed2 = ch + seed1 + seed2 + (seed2 << 5) + 3;
    }

    return seed1;
}

uint32_t mpq_hash_data(const void* data, size_t length, uint32_t type) {
    assert(crypt_table_initialized);
    assert(data);
    
	const uint8_t* data_stream = data;
	const uint8_t* data_stream_end = BUFFER_OFFSET(data, length);
	
    uint32_t seed1 = 0x7FED7FED;
    uint32_t seed2 = 0xEEEEEEEE;
    uint32_t shifted_type = (type << 8);
    uint32_t ch;
    
    while (data_stream < data_stream_end) {
        ch = *data_stream++;

        seed1 = crypt_table[shifted_type + ch] ^ (seed1 + seed2);
        seed2 = ch + seed1 + seed2 + (seed2 << 5) + 3;
    }

    return seed1;
}

void mpq_crc32(const void* buffer, size_t length, uint32_t* crc, uint32_t flags) {
    uint32_t local_crc = 0;
    
	const uint8_t* data_stream = buffer;
	const uint8_t* data_stream_end = BUFFER_OFFSET(buffer, length);
    
    if (crc) local_crc = *crc;
    if (flags & MPQ_CRC_INIT) local_crc = 0xFFFFFFFF;
    
    if (flags & MPQ_CRC_UPDATE) {
        while (data_stream < data_stream_end) {
			// explicit cast is OK here, crc32 is 32-bit
            local_crc = ((local_crc >> 8) & 0x00FFFFFF) ^ (uint32_t)crc_table[(local_crc ^ *data_stream) & 0xFF];
            data_stream++;
        }
    }
    
    if (flags & MPQ_CRC_FINALIZE) local_crc = local_crc ^ 0xFFFFFFFF;
    if (crc) *crc = local_crc;
}

int mpq_verify_weak_signature(RSA* public_key, const void* signature, const void* digest) {
    unsigned char reversed_signature[MPQ_WEAK_SIGNATURE_SIZE];
    memcpy(reversed_signature, BUFFER_OFFSET(signature, 8), MPQ_WEAK_SIGNATURE_SIZE);
    memrev(reversed_signature, MPQ_WEAK_SIGNATURE_SIZE);
    
    return RSA_verify(NID_md5, digest, MD5_DIGEST_LENGTH, reversed_signature, MPQ_WEAK_SIGNATURE_SIZE, public_key);
}

int mpq_verify_strong_signature(RSA* public_key, const void* signature, const void* digest) {
    unsigned char reversed_signature[MPQ_STRONG_SIGNATURE_SIZE];
    memcpy(reversed_signature, BUFFER_OFFSET(signature, 4), MPQ_STRONG_SIGNATURE_SIZE);
    memrev(reversed_signature, MPQ_STRONG_SIGNATURE_SIZE);

    unsigned char real_digest[MPQ_STRONG_SIGNATURE_SIZE];
    memset(real_digest, 0xbb, sizeof(real_digest));
    real_digest[0] = 0x0b;

    size_t digest_offset = sizeof(real_digest) - SHA_DIGEST_LENGTH;
    memcpy(real_digest + digest_offset, digest, SHA_DIGEST_LENGTH);
    memrev(real_digest + digest_offset, SHA_DIGEST_LENGTH);

    RSA_public_decrypt(MPQ_STRONG_SIGNATURE_SIZE, reversed_signature, reversed_signature, public_key, RSA_NO_PADDING);
    unsigned long error = ERR_get_error();

    return (!error && memcmp(reversed_signature, real_digest, MPQ_STRONG_SIGNATURE_SIZE) == 0);
}
