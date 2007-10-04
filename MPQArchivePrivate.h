/*
 *  MPQArchivePrivate.h
 *  MPQKit
 *
 *  Created by Jean-Francois Roy on 05/07/2007.
 *  Copyright 2007 MacStorm. All rights reserved.
 *
 */

#import <MPQKit/MPQArchive.h>

@interface MPQArchive (MPQArchivePrivate)
- (uint32_t)findHashPosition:(const char *)filename locale:(uint16_t)locale error:(NSError **)error;
- (char **)_filenameTable;
- (mpq_hash_table_entry_t *)_hashTable;
- (mpq_block_table_entry_t *)_blockTable;
@end
