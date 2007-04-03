/*
 *  MPQCryptography.c
 *  MPQKit
 *
 *  Created by Jean-Francois Roy on Sat Oct 05 2002.
 *  Copyright (c) 2002 MacStorm. All rights reserved.
 *
 */

#include <assert.h>
#include <string.h>
#include <zlib.h>

#include <CoreFoundation/CFByteOrder.h>

#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/md5.h>
#include <openssl/obj_mac.h>
#include <openssl/sha.h>

#include "MPQCryptography.h"

static Boolean crypt_table_initialized = FALSE;
static uint32_t crypt_table[0x500];

static void memrev(unsigned char *buf, size_t count) {
    unsigned char *r;
    for (r = buf + count - 1; buf < r; buf++, r--) {
        *buf ^= *r;
        *r   ^= *buf;
        *buf ^= *r;
    }
}

const uint32_t *mpq_get_cryptography_table() {
    assert(crypt_table_initialized);
    return crypt_table;
}

void mpq_init_cryptography() {
    // Prepare crypt_table
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
    
    // Load up OpenSSL
    OpenSSL_add_all_digests();
    OpenSSL_add_all_algorithms();
    OpenSSL_add_all_ciphers();
    ERR_load_crypto_strings();
}

void mpq_encrypt(char *data, uint32_t length, uint32_t key, bool disable_input_swapping) {
    assert(crypt_table_initialized);
    assert(data);
    
    uint32_t *buffer32 = (uint32_t *)data;
    uint32_t seed = 0xEEEEEEEE;
    uint32_t ch;
    
    // Round to 4 bytes
    length = length / 4;
    
    // We duplicate the loop to avoid costly branches
    if (disable_input_swapping) {
        while (length-- > 0) {
            seed += crypt_table[0x400 + (key & 0xFF)];
            ch = *buffer32 ^ (key + seed);
            
            key = ((~key << 0x15) + 0x11111111) | (key >> 0x0B);
            seed = *buffer32 + seed + (seed << 5) + 3;
            
            *buffer32++ = CFSwapInt32HostToLittle(ch);
        }
    } else {
        while (length-- > 0) {
            *buffer32 = CFSwapInt32LittleToHost(*buffer32);
            
            seed += crypt_table[0x400 + (key & 0xFF)];
            ch = *buffer32 ^ (key + seed);
            
            key = ((~key << 0x15) + 0x11111111) | (key >> 0x0B);
            seed = *buffer32 + seed + (seed << 5) + 3;
            
            *buffer32++ = CFSwapInt32HostToLittle(ch);
        }
    }
}

void mpq_decrypt(char *data, uint32_t length, uint32_t key, bool disable_output_swapping) {
    assert(crypt_table_initialized);
    assert(data);
    
    uint32_t *buffer32 = (uint32_t *)data;
    uint32_t seed = 0xEEEEEEEE;
    uint32_t ch;
    
    // Round to 4 bytes
    length = length / 4;
    
    if (disable_output_swapping) {
        while (length-- > 0) {
            *buffer32 = CFSwapInt32LittleToHost(*buffer32);
            
            seed += crypt_table[0x400 + (key & 0xFF)];
            ch = *buffer32 ^ (key + seed);
            
            key = ((~key << 0x15) + 0x11111111) | (key >> 0x0B);
            seed = ch + seed + (seed << 5) + 3;
            
            *buffer32++ = ch;
        }
        
    } else {
        while (length-- > 0) {
            *buffer32 = CFSwapInt32LittleToHost(*buffer32);
            
            seed += crypt_table[0x400 + (key & 0xFF)];
            ch = *buffer32 ^ (key + seed);
            
            key = ((~key << 0x15) + 0x11111111) | (key >> 0x0B);
            seed = ch + seed + (seed << 5) + 3;
            
            *buffer32++ = CFSwapInt32HostToLittle(ch);
        }
    }
}

uint32_t mpq_hash_cstring(const char *string, uint32_t type) {
    assert(crypt_table_initialized);
    assert(string);
    
    uint32_t seed1 = 0x7FED7FED;
    uint32_t seed2 = 0xEEEEEEEE;
    uint32_t shifted_type = (type << 8);
    int32_t ch;
    
    while (*string != 0) {
        ch = *string++;
        if (ch > 0x60 && ch < 0x7b) ch -= 0x20;

        seed1 = crypt_table[shifted_type + ch] ^ (seed1 + seed2);
        seed2 = ch + seed1 + seed2 + (seed2 << 5) + 3;
    }

    return seed1;
}

uint32_t mpq_hash_data(const char *data, uint32_t length, uint32_t type) {
    assert(crypt_table_initialized);
    assert(data);
    
    uint32_t seed1 = 0x7FED7FED;
    uint32_t seed2 = 0xEEEEEEEE;
    uint32_t shifted_type = (type << 8);
    int32_t ch;
    
    while (length > 0) {
        ch = *data++;

        seed1 = crypt_table[shifted_type + ch] ^ (seed1 + seed2);
        seed2 = ch + seed1 + seed2 + (seed2 << 5) + 3;
        length--;
    }

    return seed1;
}

void mpq_crc32(const unsigned char *buffer, uint32_t length, uint32_t *crc, uint32_t flags) {
    uint32_t local_crc = 0;
    const uint32_t *crc_table = (uint32_t *)get_crc_table();
    const unsigned char *buffer_end = buffer + length;
    
    if (crc) local_crc = *crc;
    if (flags & MPQ_CRC_INIT) local_crc = 0xFFFFFFFF;
    
    if (flags & MPQ_CRC_UPDATE) {
        while (buffer < buffer_end) {
            local_crc = ((local_crc >> 8) & 0x00FFFFFF) ^ crc_table[(local_crc ^ *buffer) & 0xFF];
            buffer++;
        }
    }
    
    if (flags & MPQ_CRC_FINALIZE) local_crc = local_crc ^ 0xFFFFFFFF;
    if (crc) *crc = local_crc;
}

int mpq_verify_weak_signature(RSA *public_key, const unsigned char *signature, const unsigned char *digest) {
    unsigned char reversed_signature[MPQ_WEAK_SIGNATURE_SIZE];
    memcpy(reversed_signature, signature + 8, MPQ_WEAK_SIGNATURE_SIZE);
    memrev(reversed_signature, MPQ_WEAK_SIGNATURE_SIZE);
    
    return RSA_verify(NID_md5, digest, MD5_DIGEST_LENGTH, reversed_signature, MPQ_WEAK_SIGNATURE_SIZE, public_key);
}

int mpq_verify_strong_signature(RSA *public_key, const unsigned char *signature, const unsigned char *digest) {
    unsigned char reversed_signature[MPQ_STRONG_SIGNATURE_SIZE];
    memcpy(reversed_signature, signature + 4, MPQ_STRONG_SIGNATURE_SIZE);
    memrev(reversed_signature, MPQ_STRONG_SIGNATURE_SIZE);

    unsigned char real_digest[MPQ_STRONG_SIGNATURE_SIZE];
    memset(real_digest, 0xbb, sizeof(real_digest));
    real_digest[0] = 0x0b;

    uint32_t digest_offset = sizeof(real_digest) - SHA_DIGEST_LENGTH;
    memcpy(real_digest + digest_offset, digest, SHA_DIGEST_LENGTH);
    memrev(real_digest + digest_offset, SHA_DIGEST_LENGTH);

    RSA_public_decrypt(MPQ_STRONG_SIGNATURE_SIZE, reversed_signature, reversed_signature, public_key, RSA_NO_PADDING);
    unsigned long error = ERR_get_error();

    return (!error && memcmp(reversed_signature, real_digest, MPQ_STRONG_SIGNATURE_SIZE) == 0);
}
