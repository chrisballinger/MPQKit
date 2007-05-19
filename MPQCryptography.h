/*
 *  MPQCryptography.h
 *  MPQKit
 *
 *  Created by Jean-Francois Roy on Sat Oct 05 2002.
 *  Copyright (c) 2002-2007 MacStorm. All rights reserved.
 *
 */

#include <stdbool.h>
#include <stdint.h>
#include <openssl/rsa.h>

#if defined(__cplusplus)
extern "C" {
#endif

#if !defined(MPQ_WEAK_SIGNATURE_SIZE)
    #define MPQ_WEAK_SIGNATURE_SIZE 64
#endif

#if !defined(MPQ_STRONG_SIGNATURE_SIZE)
    #define MPQ_STRONG_SIGNATURE_SIZE 256
#endif

extern void mpq_init_cryptography(void);

extern const uint32_t *mpq_get_cryptography_table(void);

extern void mpq_encrypt(char *data, uint32_t length, uint32_t key, bool disable_input_swapping);
extern void mpq_decrypt(char *data, uint32_t length, uint32_t key, bool disable_output_swapping);

extern uint32_t mpq_hash_cstring(const char *string, uint32_t type);
extern uint32_t mpq_hash_data(const char *data, uint32_t length, uint32_t type);

#define MPQ_CRC_INIT 0x1
#define MPQ_CRC_UPDATE 0x2
#define MPQ_CRC_FINALIZE 0x4
extern void mpq_crc32(const unsigned char *buffer, uint32_t length, uint32_t *crc, uint32_t flags);

int mpq_verify_weak_signature(RSA *public_key, const unsigned char *signature, const unsigned char *digest);
int mpq_verify_strong_signature(RSA *public_key, const unsigned char *signature, const unsigned char *digest);

#if defined(__cplusplus)
}
#endif
