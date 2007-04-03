//
//  NSDataCryptoAdditions.m
//  MPQKit
//
//  Created by Jean-François Roy on 14/10/2006.
//  Copyright 2006 DamienBob. All rights reserved.
//

#include <openssl/md5.h>
#include <openssl/sha.h>

#import "NSDataCryptoAdditions.h"

@implementation NSData(CryptographicAdditions)

#define HEComputeDigest(method)                                                                 \
    method##_CTX ctx;                                                                           \
    unsigned char digest[method##_DIGEST_LENGTH];                                               \
    method##_Init(&ctx);                                                                        \
    method##_Update(&ctx, [self bytes], [self length]);                                         \
    method##_Final(digest, &ctx);

#define HEComputeDigestNSData(method)                                                           \
    HEComputeDigest(method)                                                                     \
    return [NSData dataWithBytes:digest length:method##_DIGEST_LENGTH];

#define HEComputeDigestNSString(method)                                                         \
    static char __HEHexDigits[] = "0123456789abcdef";                                           \
    unsigned char digestString[2*method##_DIGEST_LENGTH];                                       \
    unsigned int i;                                                                             \
    HEComputeDigest(method)                                                                     \
    for(i=0; i<method##_DIGEST_LENGTH; i++) {                                                   \
        digestString[2*i]   = __HEHexDigits[digest[i] >> 4];                                    \
        digestString[2*i+1] = __HEHexDigits[digest[i] & 0x0f];                                  \
    }                                                                                           \
    return [NSString stringWithCString:(char *)digestString length:2*method##_DIGEST_LENGTH];

#define SHA1_CTX                SHA_CTX
#define SHA1_DIGEST_LENGTH      SHA_DIGEST_LENGTH

- (NSData *)md5 {
    HEComputeDigestNSData(MD5);
}

- (NSString *)md5String {
    HEComputeDigestNSString(MD5);
}

- (NSData *)sha1 {
    HEComputeDigestNSData(SHA1);
}

- (NSString *)sha1String {
    HEComputeDigestNSString(SHA1);
}

@end
