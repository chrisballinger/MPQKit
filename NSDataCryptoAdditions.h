//
//  NSDataCryptoAdditions.h
//  MPQKit
//
//  Created by Jean-François Roy on 14/10/2006.
//  Copyright 2006 DamienBob. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (CryptographicAdditions)
- (NSData *)md5;
- (NSString *)md5String;

- (NSData *)sha1;
- (NSString *)sha1String;
@end
