//
//	MPQArchive.m
//	MPQKit
//
//	Created by Jean-Francois Roy on Tue Oct 01 2002.
//	Copyright (c) 2002-2007 MacStorm. All rights reserved.
//

#if !defined(__APPLE__)
#define _XOPEN_SOURCE 600
#define _FILE_OFFSET_BITS  64
#endif
 
#import <fcntl.h>
#import <unistd.h>
#import <zlib.h>
#import <aio.h>

#import <sys/stat.h>
#import <sys/types.h>

#import <openssl/bio.h>
#import <openssl/md5.h>
#import <openssl/pem.h>
#import <openssl/sha.h>

#import "SCompression.h"

#import "MPQKitPrivate.h"
#import "MPQFileInfoEnumerator.h"

#import "mpqdebug.h"
#import "PHSErrorMacros.h"

#if defined(GNUSTEP)
@interface NSError(GSCategories)
+ (NSError*)_last;
@end
#endif

#define BUFFER_OFFSET(buffer, bytes) ((uint8_t*)buffer + (bytes))

// magic numbers in big endian
#define MPQ_MAGIC 0x4D50511A
#define MPQ_SHUNT_MAGIC 0x4D50511B
#define ATTRIBUTES_MAGIC 0x64
#define STRONG_SIGNATURE_MAGIC 0x4E474953

// Hashing mode constants
#define HASH_POSITION 0
#define HASH_NAME_A 1
#define HASH_NAME_B 2
#define HASH_KEY 3

// Special values for a hash table entry's block table entry index
#define HASH_TABLE_EMPTY 0xffffffff
#define HASH_TABLE_DELETED 0xfffffffe

// This is the only valid sector size shift factor as of right now
#define DEFAULT_SECTOR_SIZE_SHIFT 3

// We don't want to compress any files smaller than 0x20 bytes
#define COMPRESSION_THRESHOLD 0x20

// Special MPQ strings
static const char* kBlockTableEncryptionKey = "(block table)";
static const char* kHashTableEncryptionKey	= "(hash table)";
static const char* kSignatureEncryptionKey	= "(signature)";

// Special MPQ strings, Obj-C versions
static NSString* kListfileFilename			= @"(listfile)";
static NSString* kAttributesFilename		= @"(attributes)";
static NSString* kSignatureFilename			= @"(signature)";

struct mpq_file_attribute_t {
	uint32_t flag;
	uint32_t size;
	NSString* key;
	NSString* getter;
	NSString* setter;
};
typedef struct mpq_file_attribute_t mpq_file_attribute_t;

static mpq_file_attribute_t mpq_file_attributes[] = {
	{0x01, 4, @"CRC", @"getCRC:", @"setCRC:forValue:"},
	{0x02, 8, @"CreationDate", @"getCreationDate:", @"setCreationDate:forValue:"},
	{0x04, 16, @"MD5Sum", @"getMD5:", @"setMD5:forValue:"},
	{0, 0, nil, nil, nil},
};

// Bundled RSA keys
static RSA* blizzard_strong_public_rsa		= NULL;
static RSA* warcraft3_map_public_rsa		= NULL;
static RSA* wow_survey_public_rsa			= NULL;
static RSA* wow_mac_patch_public_rsa		= NULL;
static RSA* starcraft_map_public_rsa		= NULL;

static RSA* blizzard_weak_public_rsa		= NULL;

static int _MPQMakeTempFileInDirectory(NSString* directory, NSString** tempFilePath, NSError** error) {
	char* template = malloc(PATH_MAX + 1);
	if (!template) ReturnValueWithError(-1, MPQErrorDomain, errOutOfMemory, nil, error)
	
	if (!directory) directory = NSTemporaryDirectory();
	[[directory stringByAppendingPathComponent:@".org.macstorm.mpqkit-XXXXXXXX"] getFileSystemRepresentation:template maxLength:PATH_MAX + 1];
	
	int fd = mkstemp(template);
	if (fd == -1) {
		free(template);
		ReturnValueWithPOSIXError(-1, nil, error)
	}
	
	if (tempFilePath) *tempFilePath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:template length:strlen(template)];
	
	free(template);
	ReturnValueWithNoError(fd, error)
}

static inline BOOL _MPQFSCopy(NSString* destination, NSString* source, NSError** error) {
#if defined(__APPLE__)
	OSStatus err = FSPathCopyObjectSync([source UTF8String], 
										[[destination stringByDeletingLastPathComponent] UTF8String], 
										(CFStringRef)[destination lastPathComponent], 
										NULL, 
										kFSFileOperationOverwrite);
	if (err != noErr) ReturnValueWithError(NO, NSOSStatusErrorDomain, err, nil, error)
	ReturnValueWithNoError(YES, error)
#elif defined(GNUSTEP)
	BOOL err = [[NSFileManager defaultManager] copyPath:source toPath:destination handler:nil];
	if (err && error) *error = [NSError _last];
	return err;
#else
#  error Not implemented
#endif
}

static inline BOOL _MPQFSMove(NSString* destination, NSString* source, NSError** error) {
#if defined(__APPLE__)
	OSStatus err = FSPathMoveObjectSync([source UTF8String], 
										[[destination stringByDeletingLastPathComponent] UTF8String], 
										(CFStringRef)[destination lastPathComponent], 
										NULL, 
										kFSFileOperationOverwrite);
	if (err != noErr) ReturnValueWithError(NO, NSOSStatusErrorDomain, err, nil, error)
	ReturnValueWithNoError(YES, error)
#elif defined(GNUSTEP)
	BOOL err = [[NSFileManager defaultManager] movePath:source toPath:destination handler:nil];
	if (err && error) *error = [NSError _last];
	return err;
#else
#  error Not implemented
#endif
}

char* _MPQCreateASCIIFilename(NSString* filename, NSError** error) {
	size_t filename_csize = [filename lengthOfBytesUsingEncoding:NSASCIIStringEncoding] + 1;
	if (filename_csize > MPQ_MAX_PATH) ReturnValueWithError(NULL, MPQErrorDomain, errFilenameTooLong, nil, error)
	
	char* filename_cstring = malloc(filename_csize);
	if (!filename_cstring) ReturnValueWithError(NULL, MPQErrorDomain, errOutOfMemory, nil, error)
	
	if (![filename getCString:filename_cstring maxLength:filename_csize encoding:NSASCIIStringEncoding]) {
		free(filename_cstring);
		ReturnValueWithError(NULL, MPQErrorDomain, errCouldNotConvertFilenameToASCII, nil, error)
	}
	
	ReturnValueWithNoError(filename_cstring, error)
}

static inline uint32_t _MPQComputeSectorTableLength(uint32_t full_sector_size, uint32_t file_size, uint32_t file_flags) {
	uint32_t sector_table_length = ((file_size + full_sector_size - 1) / full_sector_size) + 1;
	if ((file_flags & MPQFileHasSectorAdlers)) sector_table_length++;
	return sector_table_length;
}


@interface MPQFile (Initialization)
- (id)initForFile:(NSDictionary*)descriptor error:(NSError**)error;
@end


@implementation MPQArchive

+ (RSA*)RSAWithContentsOfPublicKeyPEMFile:(NSString*)path {
	RSA* key = NULL;
	
	NSData* keyData = [[NSData alloc] initWithContentsOfFile:path];
	if (!keyData) return NULL;
	
	// Cast to int is necessary since that's what BIO_new_mem_buf takes
	BIO* keyBIO = BIO_new_mem_buf((void*)[keyData bytes], (int)[keyData length]);
	if (!keyBIO) goto FreeData;
	
	key = PEM_read_bio_RSA_PUBKEY(keyBIO, &key, NULL, NULL);
	BIO_free(keyBIO);

FreeData:
	[keyData release];
	return key;
}

+ (void)initialize {
	static BOOL _MPQArchive_has_initialized = NO;
	if (!_MPQArchive_has_initialized) {
		_MPQArchive_has_initialized = YES;
		
		mpq_init_cryptography();
		
#if !defined(GNUSTEP)
		NSBundle* kitBundle = [NSBundle bundleForClass:self];
		NSString* keyPath = [kitBundle pathForResource:@"Blizzard Strong" ofType:@"pem" inDirectory:@"Public RSA Keys"];
		blizzard_strong_public_rsa = [self RSAWithContentsOfPublicKeyPEMFile:keyPath];
		
		keyPath = [kitBundle pathForResource:@"Warcraft 3 Map" ofType:@"pem" inDirectory:@"Public RSA Keys"];
		warcraft3_map_public_rsa = [self RSAWithContentsOfPublicKeyPEMFile:keyPath];
		
		keyPath = [kitBundle pathForResource:@"World of Warcraft Survey" ofType:@"pem" inDirectory:@"Public RSA Keys"];
		wow_survey_public_rsa = [self RSAWithContentsOfPublicKeyPEMFile:keyPath];
		
		keyPath = [kitBundle pathForResource:@"World of Warcraft Macintosh Patch" ofType:@"pem" inDirectory:@"Public RSA Keys"];
		wow_mac_patch_public_rsa = [self RSAWithContentsOfPublicKeyPEMFile:keyPath];
		
		keyPath = [kitBundle pathForResource:@"StarCraft Map" ofType:@"pem" inDirectory:@"Public RSA Keys"];
		starcraft_map_public_rsa = [self RSAWithContentsOfPublicKeyPEMFile:keyPath];
		
		keyPath = [kitBundle pathForResource:@"Blizzard Weak" ofType:@"pem" inDirectory:@"Public RSA Keys"];
		blizzard_weak_public_rsa = [self RSAWithContentsOfPublicKeyPEMFile:keyPath];
#endif
	}
}

+ (NSString*)localeName:(MPQLocale)locale {
	switch(locale) {
		case MPQNeutral: return nil;
		case MPQChinese: return @"Chinese";
		case MPQCzech: return @"Czech";
		case MPQGerman: return @"German";
		case MPQEnglish: return @"English";
		case MPQSpanish: return @"Spanish";
		case MPQFrench: return @"French";
		case MPQItalian: return @"Italian";
		case MPQJapanese: return @"Japanese";
		case MPQKorean: return @"Korean";
		case MPQDutch: return @"Dutch";
		case MPQPolish: return @"Polish";
		case MPQPortuguese: return @"Portuguese";
		case MPQRusssian: return @"Russsian";
		case MPQEnglishUK: return @"English UK";
	}
	return nil;
}

#if defined(__APPLE__)
+ (NSLocale*)localeForMPQLocale:(MPQLocale)locale {
	switch(locale) {
		case MPQNeutral: return nil;
		case MPQChinese: return [[[NSLocale alloc] initWithLocaleIdentifier:@"zh"] autorelease];
		case MPQCzech: return [[[NSLocale alloc] initWithLocaleIdentifier:@"cs"] autorelease];
		case MPQGerman: return [[[NSLocale alloc] initWithLocaleIdentifier:@"de"] autorelease];
		case MPQEnglish: return [[[NSLocale alloc] initWithLocaleIdentifier:@"en_US"] autorelease];
		case MPQSpanish: return [[[NSLocale alloc] initWithLocaleIdentifier:@"es"] autorelease];
		case MPQFrench: return [[[NSLocale alloc] initWithLocaleIdentifier:@"fr"] autorelease];
		case MPQItalian: return [[[NSLocale alloc] initWithLocaleIdentifier:@"it"] autorelease];
		case MPQJapanese: return [[[NSLocale alloc] initWithLocaleIdentifier:@"ja"] autorelease];
		case MPQKorean: return [[[NSLocale alloc] initWithLocaleIdentifier:@"ko"] autorelease];
		case MPQDutch: return [[[NSLocale alloc] initWithLocaleIdentifier:@"nl"] autorelease];
		case MPQPolish: return [[[NSLocale alloc] initWithLocaleIdentifier:@"pl"] autorelease];
		case MPQPortuguese: return [[[NSLocale alloc] initWithLocaleIdentifier:@"pt"] autorelease];
		case MPQRusssian: return [[[NSLocale alloc] initWithLocaleIdentifier:@"ru"] autorelease];
		case MPQEnglishUK: return [[[NSLocale alloc] initWithLocaleIdentifier:@"en_GB"] autorelease];
	}
	return nil;
}
#endif

#pragma mark byte order methods

+ (void)swap_uint32_array:(uint32_t*)array length:(uint32_t)length {
#if defined(__BIG_ENDIAN__)
	uint32_t i = 0;
	while (i < length) {
		array[i] = MPQSwapInt32(array[i]);
		i++;
	}
#endif
}

+ (void)swap_mpq_header:(mpq_header_t*)header {
#if defined(__BIG_ENDIAN__)
	header->header_size = MPQSwapInt32(header->header_size);
	header->archive_size = MPQSwapInt32(header->archive_size);
	header->version = MPQSwapInt16(header->version);
	header->sector_size_shift = MPQSwapInt16(header->sector_size_shift);
	header->hash_table_offset = MPQSwapInt32(header->hash_table_offset);
	header->block_table_offset = MPQSwapInt32(header->block_table_offset);
	header->hash_table_length = MPQSwapInt32(header->hash_table_length);
	header->block_table_length = MPQSwapInt32(header->block_table_length);
#else
	header->mpq_magic = MPQSwapInt32(header->mpq_magic);
#endif
}

+ (void)swap_mpq_shunt:(mpq_shunt_t*)shunt {
#if defined(__BIG_ENDIAN__)
	shunt->unknown04 = MPQSwapInt32(shunt->unknown04);
	shunt->mpq_header_offset = MPQSwapInt32(shunt->mpq_header_offset);
#else
	shunt->shunt_magic = MPQSwapInt32(shunt->shunt_magic);
#endif
}

+ (void)swap_mpq_extended_header:(mpq_extended_header_t*)header {
#if defined(__BIG_ENDIAN__)
	header->extended_block_offset_table_offset = MPQSwapInt64(header->extended_block_offset_table_offset);
	header->hash_table_offset_high = MPQSwapInt16(header->hash_table_offset_high);
	header->block_table_offset_high = MPQSwapInt16(header->block_table_offset_high);
#endif
}

- (void)swap_hash_table {
#if defined(__BIG_ENDIAN__)
	uint32_t i = 0;
	while (i < header.hash_table_length) {
		(hash_table + i)->hash_a = MPQSwapInt32((hash_table + i)->hash_a);
		(hash_table + i)->hash_b = MPQSwapInt32((hash_table + i)->hash_b);
		(hash_table + i)->locale = MPQSwapInt16((hash_table + i)->locale);
		(hash_table + i)->platform = MPQSwapInt16((hash_table + i)->platform);
		(hash_table + i)->block_table_index = MPQSwapInt32((hash_table + i)->block_table_index);
		i++;
	}
#endif
}

- (void)swap_extended_block_offset_table:(mpq_extended_block_offset_table_entry_t*)table length:(uint32_t)length {
#if defined(__BIG_ENDIAN__)
	uint32_t i = 0;
	while (i < length) {
		(table + i)->offset_high = MPQSwapInt16((table + i)->offset_high);
		i++;
	}
#endif
}

#pragma mark encryption keys

- (uint32_t)getFileEncryptionKey:(uint32_t)hash_position name:(const char*)filename {
	NSParameterAssert(filename != NULL);
	NSParameterAssert(hash_position < header.hash_table_length);

	// Check if we have a cached key
	if (encryption_keys_cache[hash_position] != 0) return encryption_keys_cache[hash_position];
	
	// Alias to the file table entry
	mpq_hash_table_entry_t* hash_entry = hash_table + hash_position;
	mpq_block_table_entry_t* block_entry = block_table + hash_entry->block_table_index;
	
	uint32_t encryption_key;
	
	// The encryption key is based on the file name, not the path
	const char* key = strrchr(filename, '\\');
	if (!key) key = filename;
	else key++;
		
	// Compute the encryption key
	encryption_key = mpq_hash_cstring(key, HASH_KEY);
		
	// Offset adjust the key if necessary
	if ((block_entry->flags & MPQFileOffsetAdjustedKey)) {
		encryption_key = (encryption_key + (uint32_t)(block_offset_table[hash_entry->block_table_index])) ^ block_entry->size;
	}
		
	encryption_keys_cache[hash_position] = encryption_key;
	return encryption_key;
}

- (uint32_t)getFileEncryptionKey:(uint32_t)hash_position {
	NSParameterAssert(hash_position < header.hash_table_length);
	
	// Check if we have a cached key.
	if (encryption_keys_cache[hash_position] != 0) return encryption_keys_cache[hash_position];
	
	// If we have the filename, redirect to the normal method
	if (filename_table[hash_position]) return [self getFileEncryptionKey:hash_position name:filename_table[hash_position]];
	
	// Alias to the block table entry
	mpq_hash_table_entry_t* hash_entry = hash_table + hash_position;
	mpq_block_table_entry_t* block_entry = block_table + hash_entry->block_table_index;
	
	// We can attempt a brute force attack if the file is compressed (multiple sectors only)
	if ((block_entry->flags & (MPQFileCompressed | MPQFileDiabloCompressed)) && !(block_entry->flags & MPQFileOneSector)) {
		uint32_t encryption_key;
		const uint32_t* crypt_table = mpq_get_cryptography_table();
		
		uint32_t sector_table_length = _MPQComputeSectorTableLength(full_sector_size, block_entry->size, block_entry->flags);
		// Explicit cast is OK here because the encryption algorithm works with 32-bit integers
		uint32_t sector_table_size = sector_table_length * (uint32_t)sizeof(uint32_t);
		
		// First we read the first 2 sector table entries. This should work because no compressed file has fewer than 2 entries.
		uint32_t sector_table[2];
		if (pread(archive_fd, sector_table, 8, archive_offset + block_offset_table[hash_entry->block_table_index]) < 8) return 0;
		
		// Byte order
		sector_table[0] = MPQSwapInt32LittleToHost(sector_table[0]);
		sector_table[1] = MPQSwapInt32LittleToHost(sector_table[1]);
		
		// Next we do some preliminary computations...
		uint32_t temp = sector_table[0] ^ sector_table_size;	// temp = seed1 + seed2
		temp -= 0xEEEEEEEE;										// temp = seed1 + lpdwCryptTable[0x400 + (seed1 & 0xFF)] + 0xEEEEEEEE
																// temp = seed1 + lpdwCryptTable[0x400 + (seed1 & 0xFF)]
		
		uint32_t i = 0;
		for (i = 0; i < 0x100; i++) {
			uint32_t seed1;
			uint32_t seed2 = 0xEEEEEEEE;
			uint32_t ch;
			uint32_t ch2;
			
			// Try to decrypt the first sector table entry (we exactly
			// know the value, since it's always the number of bytes in
			// the sector table).
			seed1  = temp - crypt_table[0x400 + i];
			seed2 += crypt_table[0x400 + (seed1 & 0xFF)];
			ch	   = sector_table[0] ^ (seed1 + seed2);
			
			if (ch != sector_table_size) continue;
			
			// Add 1 because we are decrypting block positions
			encryption_key = seed1 + 1;
			ch2 = ch;
			
			// If the first entry checks out, we can check the second. We
			// don't know the exact value, but we know that no block will
			// be larger than full_sector_size.
			seed1  = ((~seed1 << 0x15) + 0x11111111) | (seed1 >> 0x0B);
			seed2  = ch + seed2 + (seed2 << 5) + 3;
			
			seed2 += crypt_table[0x400 + (seed1 & 0xFF)];
			ch	   = sector_table[1] ^ (seed1 + seed2);
			
			if ((ch - ch2) <= full_sector_size) {
				encryption_keys_cache[hash_position] = encryption_key;
				return encryption_key;
			}
		}
	}
	
	// Out of luck
	return 0;
}

#pragma mark file management

- (BOOL)_truncateArchiveWithDelta:(off_t)delta error:(NSError**)error {
	NSParameterAssert(archive_size + delta > 0);
	if (archive_fd == -1) ReturnValueWithError(NO, MPQErrorDomain, errNoArchiveFile, nil, error)
	
	struct stat sb;
	if (fstat(archive_fd, &sb) == -1) ReturnValueWithPOSIXError(NO, nil, error)
	
	// If the extra data is exactly a strong signature, we continue
	if (sb.st_size != archive_offset + archive_size + ((strong_signature) ? MPQ_STRONG_SIGNATURE_SIZE + 4 : 0))
		ReturnValueWithError(NO, MPQErrorDomain, errCannotResizeArchive, nil, error)
	
	// We now consider a strong signature as lost, and so we must release its memory
	if (strong_signature) free(strong_signature);
	strong_signature = NULL;
	
	// Version 0 archives cannot be larger than UINT32_MAX
	if (header.version == 0 && archive_size + delta > UINT32_MAX) ReturnValueWithError(NO, MPQErrorDomain, errArchiveSizeOverflow, nil, error)
	
	// Resize the archive file
	if (ftruncate(archive_fd, archive_offset + archive_size + delta) == -1) ReturnValueWithPOSIXError(NO, nil, error)
	
	archive_size += delta;
	ReturnValueWithNoError(YES, error)
}

#pragma mark structural tables

- (uint32_t)createHashPosition:(const char*)filename error:(NSError**)error {
	NSParameterAssert(filename != NULL);

	// Compute the starting offset in the hash table using the filename we want to create a hash entry for.
	uint32_t initial_position = mpq_hash_cstring(filename, HASH_POSITION) % header.hash_table_length;
	uint32_t current_position = initial_position;

	// Go through the table until we find an unused hash table entry
	while (hash_table[current_position].block_table_index != HASH_TABLE_EMPTY && hash_table[current_position].block_table_index != HASH_TABLE_DELETED) {
		current_position++;
		current_position %= header.hash_table_length;

		// If there aren't any free slots, we'll search through the entire hash table. Is this what happened?
		if (current_position == initial_position) ReturnValueWithError(0xffffffff, MPQErrorDomain, errHashTableFull, nil, error)
	}
	
	ReturnValueWithNoError(current_position, error)
}

- (uint32_t)findHashPosition:(const char*)filename locale:(uint16_t)locale error:(NSError**)error {
	NSParameterAssert(filename != NULL);

	// Compute the starting hash table offset, as well as the verification hashes for the specified file.
	uint32_t initial_position = mpq_hash_cstring(filename, HASH_POSITION) % header.hash_table_length,
		current_position = initial_position,
		hash_a = mpq_hash_cstring(filename, HASH_NAME_A),
		hash_b = mpq_hash_cstring(filename, HASH_NAME_B);

	// Search through the hash table until we either find the file we're looking for, or we find an unused hash table entry, 
	// indicating the end of the cluster of used hash table entries
	while (hash_table[current_position].block_table_index != HASH_TABLE_EMPTY) {
		if (hash_table[current_position].block_table_index != HASH_TABLE_DELETED) {
			if (hash_table[current_position].hash_a == hash_a && 
				hash_table[current_position].hash_b == hash_b && 
				hash_table[current_position].locale == locale)
			{
				ReturnValueWithNoError(current_position, error)
			}
		}

		current_position++;
		current_position %= header.hash_table_length;

		// It's possible that the entire hash table is full and the file we're looking for simply doesn't exist. Is this the case?
		if (current_position == initial_position) break;
	}
	
	ReturnValueWithError(0xffffffff, MPQErrorDomain, errHashTableEntryNotFound, nil, error)
}

- (off_t)_computeSizeOfStructuralTables {
	off_t structural_size = (header.hash_table_length * sizeof(mpq_hash_table_entry_t)) + (header.block_table_length * sizeof(mpq_block_table_entry_t));
	if (extended_header.extended_block_offset_table_offset != 0) structural_size += header.block_table_length * sizeof(mpq_extended_block_offset_table_entry_t);
	return structural_size;
}

- (BOOL)_growBlockTable:(NSError**)error {
	if (header.block_table_length == UINT32_MAX) ReturnValueWithError(NO, MPQErrorDomain, errBlockTableFull, nil, error)
	
	// Save the current block table length and the corresponding structural tables size
	uint32_t old_block_table_length = header.block_table_length;
//	  off_t old_structural_tables_size = [self _computeSizeOfStructuralTables];
	
	// Increase the block table length and compute the corrresponding structural tables size
	header.block_table_length += 128;
	if (header.block_table_length < old_block_table_length) header.block_table_length = UINT32_MAX;
//	  off_t new_structural_tables_size = [self _computeSizeOfStructuralTables];
	
	// Resize the archive
//	  if (![self _truncateArchiveWithDelta:new_structural_tables_size - old_structural_tables_size error:error]) {
//		  header.block_table_length = old_block_table_length;
//		  return NO;
//	  }
	
	// Attributes
	uint32_t attributes_data_delta = 0;
	if (attributes_data) {
		mpq_attributes_header_t* attributes = (mpq_attributes_header_t*)attributes_data;
		
		mpq_file_attribute_t* attribute = mpq_file_attributes;
		while (attribute->flag != 0) {
			if ((attributes->attributes & attribute->flag)) attributes_data_delta += attribute->size;
			attribute++;
		}
		attributes_data_delta *= 128;
	}

	// Realloc the block table, the block offset table and the attributes data
	mpq_block_table_entry_t* new_block_table = realloc(block_table, header.block_table_length * sizeof(mpq_block_table_entry_t));
	off_t* new_block_offset_table = realloc(block_offset_table, header.block_table_length * sizeof(off_t));
	if (new_block_table == NULL || new_block_offset_table == NULL) {
		header.block_table_length = old_block_table_length;
		ReturnValueWithError(NO, MPQErrorDomain, errOutOfMemory, nil, error)
	}
	
	void* new_attributes_data = realloc(attributes_data, attributes_data_size + attributes_data_delta);
	if (new_attributes_data == NULL) {
		header.block_table_length = old_block_table_length;
		ReturnValueWithError(NO, MPQErrorDomain, errOutOfMemory, nil, error)
	}
	
	// Swap the pointers
	block_table = new_block_table;
	block_offset_table = new_block_offset_table;
	attributes_data = new_attributes_data;
	
	// memset the new entries to be neat
	memset(block_table + old_block_table_length, 0, 128 * sizeof(mpq_block_table_entry_t));
	memset(block_offset_table + old_block_table_length, 0, 128 * sizeof(off_t));
	memset(BUFFER_OFFSET(attributes_data, attributes_data_size), 0, attributes_data_delta);
	
	attributes_data_size += attributes_data_delta;
	
	ReturnValueWithNoError(YES, error)
}

- (uint32_t)createBlockTablePosition:(uint32_t)size error:(NSError**)error {
	uint32_t block_entry_index = 0;
	mpq_block_table_entry_t* block_table_entry = NULL;

	// Simply go until we find an empty slot or come to the end of the block table
	for (; block_entry_index < header.block_table_length; block_entry_index++) {
		block_table_entry = block_table + block_entry_index;
		
		// If we find an empty block table entry, return it
		if (block_table_entry->size == 0 && block_table_entry->archived_size == 0 && block_table_entry->flags == 0) {
			ReturnValueWithNoError(block_entry_index, error)
		}
		
		// If we are given the size of the file which will be represented by the new entry, try to recycle deleted entries
		if (size != 0) {
			// Adjust the size to include a possible sector table
			// TODO: should be able to take into account MPQFileHasSectorAdlers
			uint32_t sector_table_length = _MPQComputeSectorTableLength(full_sector_size, size, 0);
			// Explicit cast is OK here, MPQ file sizes are 32-bit
			size += sector_table_length * (uint32_t)sizeof(uint32_t);
			
			// If the current entry is invalid and the storage size is greater or equal to what we need
			if (!(block_table_entry->flags & MPQFileValid) && block_table_entry->archived_size >= size && block_offset_table[block_entry_index] > 0) {
				ReturnValueWithNoError(block_entry_index, error)
			}
		}
	}
	
	// Failed to find an empty entry, so let's try to grow the block table
	if (![self _growBlockTable:error]) return 0xffffffff;
	return [self createBlockTablePosition:size error:error];
}

#pragma mark sector table cache

- (void)flushSectorTablesCache {
	uint32_t current_sector = 0;
	for (; current_sector < header.hash_table_length; current_sector++) {
		if (sector_tables_cache[current_sector]) free(sector_tables_cache[current_sector]);
		sector_tables_cache[current_sector] = NULL;
	}
	
	memset(sector_tables_cache, 0, header.hash_table_length * sizeof(uint32_t*));
}

- (void)_cacheSectorTableForFile:(uint32_t)hash_position key:(uint32_t)encryptionKey error:(NSError**)error {
	NSParameterAssert(hash_position < header.hash_table_length);
	
	// Do nothing if that hash entry is empty or deleted
	mpq_hash_table_entry_t* hash_entry = hash_table + hash_position;
	if (hash_entry->block_table_index == HASH_TABLE_EMPTY || hash_entry->block_table_index == HASH_TABLE_DELETED) ReturnWithNoError(error)
	mpq_block_table_entry_t* block_entry = block_table + hash_entry->block_table_index;
	
	// Only compressed, multi-sector files have a sector table
	if (!(block_entry->flags & (MPQFileCompressed | MPQFileDiabloCompressed)) || (block_entry->flags & MPQFileOneSector)) ReturnWithNoError(error)

	// Calculate the number of sectors for that file and the size of the resulting sector table
	uint32_t sector_table_length = _MPQComputeSectorTableLength(full_sector_size, block_entry->size, block_entry->flags);
	// Explicit cast is OK here, sector table sizes are 32-bit
	uint32_t sector_table_size = sector_table_length * (uint32_t)sizeof(uint32_t);

	// Either we have the sector table for that file in cache, or we don't
	uint32_t* sectors = sector_tables_cache[hash_position];
	if (sectors) ReturnWithNoError(error)
	
	// We need to read the block table. Block is allocated and therefore retained
	sectors = malloc(sector_table_size);
	if (!sectors) ReturnWithError(MPQErrorDomain, errOutOfMemory, nil, error)
	
	// Read the sector table
	ssize_t bytes_read = pread(archive_fd, sectors, sector_table_size, archive_offset + block_offset_table[hash_entry->block_table_index]);
	if (bytes_read == -1) {
		free(sectors);
		ReturnWithPOSIXError(nil, error)
	}
	if ((uint32_t)bytes_read < sector_table_size) {
		free(sectors);
		ReturnWithError(MPQErrorDomain, errIO, nil, error)
	}
	
	// If the file is encrypted, decrypt the block table and disable output swapping since a block table is just an array of unsigned longs
	if ((block_entry->flags & MPQFileEncrypted)) mpq_decrypt(sectors, sector_table_size, encryptionKey - 1, YES);
	else [[self class] swap_uint32_array:sectors length:sector_table_length];
	
	// Cache the sector table
	sector_tables_cache[hash_position] = sectors;
	ReturnWithNoError(error)
}

- (void)cacheSectorTables {
	uint32_t hash_position = 0;
	while (hash_position < header.hash_table_length) {
		// Make aliases to optimize the code
		mpq_hash_table_entry_t* hash_entry = &hash_table[hash_position];
		
		// Is this a valid file?
		if (hash_entry->block_table_index != HASH_TABLE_EMPTY && hash_entry->block_table_index != HASH_TABLE_DELETED) {
			// Do we have the encryption key?
			uint32_t encryptionKey = [self getFileEncryptionKey:hash_position];
			if (encryptionKey) [self _cacheSectorTableForFile:hash_position key:encryptionKey error:(NSError**)NULL];
		}
		
		hash_position++;
	}
}

#pragma mark file count cache

- (void)_updateFileCountCaches {
	if (_fileCountCachesDirty == NO) return;
	
	// cache the file count and valid file count
	_fileCountCache = 0;
	_validFileCountCache = 0;
	for (uint32_t hash_position = 0; hash_position < header.hash_table_length; hash_position++) {
		mpq_hash_table_entry_t* e = hash_table + hash_position;
		switch (e->block_table_index) {
			case HASH_TABLE_EMPTY:
				break;
			case HASH_TABLE_DELETED:
				_fileCountCache++;
				break;
			default:
				_fileCountCache++;
				_validFileCountCache++;
		}
	}
	
	_fileCountCachesDirty = NO;
}

#pragma mark memory management

static void mpq_deferred_operation_add_context_free(mpq_deferred_operation_add_context_t* context) {
	[context->dataSourceProxy release];
	free(context);
}

static void mpq_deferred_operation_delete_context_free(mpq_deferred_operation_delete_context_t* context) {
	free(context);
}

typedef void (*deferred_operation_context_free_function)(void*);
static deferred_operation_context_free_function dosc_free_functions[] = {
	NULL, 
	(deferred_operation_context_free_function)mpq_deferred_operation_add_context_free, 
	(deferred_operation_context_free_function)mpq_deferred_operation_delete_context_free, 
	NULL};

- (void)_flushLastDO {
	if (last_operation) {
		// Backup the operation's hash table position
		uint32_t hash_position = last_operation->primary_file_context.hash_position;
		operation_hash_table[hash_position] = NULL;
		
		// Remove the operation from the operation linked list
		mpq_deferred_operation_t* old = last_operation;
		last_operation = last_operation->previous;
		
		if (old->context) dosc_free_functions[old->type](old->context);
		[old->primary_file_context.filename release];
		free(old);
		
		// Going from newest to oldest, set the hash table position's operation to the first operation matching the position
		old = last_operation;
		while (old) {
			if (old->primary_file_context.hash_position == hash_position) {
				operation_hash_table[hash_position] = old;
				break;
			}
			
			old = old->previous;
		}
		
		// Decrease the number of operations
		deferred_operations_count--;
	}
}

- (void)_flushDOS {
	while (last_operation) [self _flushLastDO];
}

- (void)freeMemory {	
	NSAutoreleasePool* p = [NSAutoreleasePool new];
	uint32_t count;
	
	if (read_buffer) {
		free(read_buffer);
		read_buffer = NULL;
	}
	
	if (compression_buffer) {
		free(compression_buffer);
		compression_buffer = NULL;
	}
	
	if (hash_table) {
		free(hash_table);
		hash_table = NULL;
	}
	
	if (block_table) {
		free(block_table);
		block_table = NULL;
	}
	
	if (block_offset_table) {
		free(block_offset_table);
		block_offset_table = NULL;
	}
	
	if (filename_table) {
		for (count = 0; count < header.hash_table_length; count++) {
			if (filename_table[count]) free((filename_table[count]));
		}
		
		free(filename_table);
		filename_table = NULL;
	}
	
	[self _flushDOS];
	if (operation_hash_table) {
		free(operation_hash_table);
		operation_hash_table = NULL;
	}
	
	if (open_file_count_table) {
		free(open_file_count_table);
		open_file_count_table = NULL;
	}
	
	if (encryption_keys_cache) {
		free(encryption_keys_cache);
		encryption_keys_cache = NULL;
	}
	
	if (sector_tables_cache) {
		[self flushSectorTablesCache];
		free(sector_tables_cache);
		sector_tables_cache = NULL;
	}
	
	if (file_info_cache) {
		for (count = 0; count < header.hash_table_length; count++) {
			if (file_info_cache[count]) [file_info_cache[count] release];
		}
		
		free(file_info_cache);
		file_info_cache = NULL;
	}
	
	[p release];
}

- (BOOL)allocateMemory {
	// For sector operations, we'll work with full_sector_size * 2 + 1 sized buffers
	uint32_t sector_buffer_size = (full_sector_size << 1) + 1;
		
	// Read buffer
	read_buffer = malloc(sector_buffer_size);
	if (!read_buffer) goto AllocateFailure;
	
	// Compression buffer
	compression_buffer = malloc(sector_buffer_size);
	if (!compression_buffer) goto AllocateFailure;
		
	// Hash table
	hash_table = malloc(header.hash_table_length * sizeof(mpq_hash_table_entry_t));
	if (!hash_table) goto AllocateFailure;
	
	// Block table
	block_table = calloc(header.block_table_length, sizeof(mpq_block_table_entry_t));
	if (!block_table) goto AllocateFailure;
	
	// Block offset table
	block_offset_table = calloc(header.block_table_length, sizeof(off_t));
	if (!block_offset_table) goto AllocateFailure;
	
	// Name table
	filename_table = calloc(header.hash_table_length, sizeof(char*));
	if (!filename_table) goto AllocateFailure;
	
	// Operations table
	operation_hash_table = calloc(header.hash_table_length, sizeof(mpq_deferred_operation_t*));
	if (!operation_hash_table) goto AllocateFailure;
	
	// MPQFile reference count table
	open_file_count_table = calloc(header.hash_table_length, sizeof(uint32_t));
	if (!open_file_count_table) goto AllocateFailure;
	
	// Encryption key cache
	encryption_keys_cache = calloc(header.hash_table_length, sizeof(uint32_t));
	if (!encryption_keys_cache) goto AllocateFailure;
	
	// Sector table cache
	sector_tables_cache = calloc(header.hash_table_length, sizeof(uint32_t*));
	if (!sector_tables_cache) goto AllocateFailure;
	
	// Attributes cache
	file_info_cache = calloc(header.hash_table_length, sizeof(NSDictionary*));
	if (!file_info_cache) goto AllocateFailure;

	// Mark every entry in the hash table as empty (0xff everywhere)
	memset(hash_table, 0xff, header.hash_table_length * sizeof(mpq_hash_table_entry_t));

	return YES;
	
AllocateFailure:
	[self freeMemory];
	return NO;
}

#pragma mark listfile

- (BOOL)_addListfileToArchive:(NSError**)error {
	NSAutoreleasePool* p = [NSAutoreleasePool new];
	
	BOOL result = NO;
	NSMutableArray* lf = [NSMutableArray arrayWithArray:[self fileList]];
	
	// First we delete the old listfile, if there is one
	[self deleteFile:kListfileFilename locale:MPQNeutral];
	
	// Process the name table
	if (lf) {
		// Add the listfile to the listfile...
		[lf addObject:kListfileFilename];
		
		// Remove all duplicate entries from the generated listfile and sort it
		[lf sortAndDeleteDuplicates];
		
		NSString* lfString = [lf componentsJoinedByString:@"\r\n"];
		NSData* listdata = [lfString dataUsingEncoding:NSASCIIStringEncoding];
		
		NSDictionary* params = [NSDictionary dictionaryWithObjectsAndKeys: 
			[NSNumber numberWithUnsignedShort:MPQNeutral], MPQFileLocale,
			[NSNumber numberWithUnsignedInt:MPQFileCompressed], MPQFileFlags,
			[NSNumber numberWithBool:YES], MPQOverwrite,
			nil];
		result = [self addFileWithData:listdata filename:kListfileFilename parameters:params error:error];
	}
	
	MPQTransferErrorAndDrainPool(error, p);
	return result;
}

- (BOOL)_addListfileEntry:(NSString*)filename error:(NSError**)error {
	NSParameterAssert(filename != NULL);
	char* filename_cstring = _MPQCreateASCIIFilename(filename, error);
	if (!filename_cstring) return NO;
	size_t filename_length = strlen(filename_cstring) + 1;
	
	// Compute the starting point and the two verification hashes we'll use to see if the file is in the hash table
	uint32_t initial_position = mpq_hash_cstring(filename_cstring, HASH_POSITION) % header.hash_table_length,
		current_position = initial_position,
		hash_a = mpq_hash_cstring(filename_cstring, HASH_NAME_A),
		hash_b = mpq_hash_cstring(filename_cstring, HASH_NAME_B);
	
	// Search through ALL possible hash table entries. There may be multiple languages of the specified file.
	while (hash_table[current_position].block_table_index != HASH_TABLE_EMPTY) {
		// If the hash table entry matches the file we're searching for and we don't already have the filename in the name table, add it.
		if (!filename_table[current_position] && hash_table[current_position].hash_a == hash_a && hash_table[current_position].hash_b == hash_b) {
			filename_table[current_position] = malloc(filename_length);
			if (filename_table[current_position]) memcpy(filename_table[current_position], filename_cstring, filename_length);
		}
		
		current_position++;
		current_position %= header.hash_table_length;

		if (current_position == initial_position) break;
	}
	
	free(filename_cstring);
	ReturnValueWithNoError(YES, error)
}

#pragma mark private inner table access

- (char**)_filenameTable {
	return filename_table;
}

- (mpq_hash_table_entry_t*)_hashTable {
	return hash_table;
}

- (mpq_block_table_entry_t*)_blockTable {
	return block_table;
}

#pragma mark complementary init

- (BOOL)_createNewArchive:(uint32_t)hash_table_length version:(uint16_t)version offset:(off_t)offset error:(NSError**)error {
	// If this parameter is 0, we set it to 1024 (default value)
	if (hash_table_length == 0) hash_table_length = 1024;
		
	// No hash table should be smaller than MPQ_MIN_HASH_TABLE_LENGTH
	uint32_t final_hash_table_length = MPQ_MIN_HASH_TABLE_LENGTH;
	
	// Hash tables cannot be larger than MPQ_MAX_HASH_TABLE_LENGTH or MPQ_MAX_EXTENDED_HASH_TABLE_LENGTH entries
	if (version == MPQOriginalVersion) {
		if (hash_table_length > MPQ_MAX_HASH_TABLE_LENGTH) hash_table_length = MPQ_MAX_HASH_TABLE_LENGTH;
	} else if (version == MPQExtendedVersion) {
		if (hash_table_length > MPQ_MAX_EXTENDED_HASH_TABLE_LENGTH) hash_table_length = MPQ_MAX_EXTENDED_HASH_TABLE_LENGTH;
	}
	
	// The number of entries in a hash table must be a power of 2. Find the first power of 2 that is >= the specified hash table size.
	while (final_hash_table_length < hash_table_length) final_hash_table_length <<= 1;
	
	// Archive offset
	archive_offset = offset;
	
	// To allow an easy upgrade to version 1, we'll reserve the extra space needed at the beginning for the version 1 header
	archive_write_offset = sizeof(mpq_header_t) + sizeof(mpq_extended_header_t);
	
	// Pure memory for now
	archive_path = nil;
	archive_fd = -1;
	
	// Fill up a (partially) valid header
	header.mpq_magic = MPQ_MAGIC;
	// Explicit cast is OK here, header_size is 32-bit
	header.header_size = (version == MPQOriginalVersion) ? (uint32_t)sizeof(mpq_header_t) : (uint32_t)(sizeof(mpq_header_t) + sizeof(mpq_extended_header_t));
	header.archive_size = 0;
	header.version = version;
	header.sector_size_shift = DEFAULT_SECTOR_SIZE_SHIFT;
	
	header.hash_table_offset = 0;
	header.block_table_offset = 0;
	
	header.hash_table_length = final_hash_table_length;
	header.block_table_length = final_hash_table_length;
	
	// Zero the version 1 extended header
	extended_header.hash_table_offset_high = 0;
	extended_header.block_table_offset_high = 0;
	extended_header.extended_block_offset_table_offset = 0;
	
	// Default sector configuration
	full_sector_size = MPQ_BASE_SECTOR_SIZE << header.sector_size_shift;
	
	// No hash table or block table has been written yet
	hash_table_offset = 0;
	block_table_offset = 0;
	
	// no files in
	_fileCountCache = 0;
	_validFileCountCache = 0;
	
	// We have no weak signature
	weak_signature_hash_entry = NULL;
	
	// Allocate our memory
	if (![self allocateMemory]) ReturnValueWithError(NO, MPQErrorDomain, errOutOfMemory, nil, error)
		
	// Since we haven't been saved yet, we are "writable"
	is_read_only = NO;
	
	// Mark the instance as dirty
	is_modified = YES;
	
	ReturnValueWithNoError(YES, error)
}

- (void)_loadAttributes:(NSError**)error {
	MPQFile* attributes_file = [self openFile:kAttributesFilename locale:MPQNeutral error:error];
	if (!attributes_file) return;
	
	attributes_data_size = [attributes_file length];
	attributes_data = malloc(attributes_data_size);
	if (!attributes_data) {
		[attributes_file release];
		ReturnWithError(MPQErrorDomain, errOutOfMemory, NULL, error)
	}
	
	if ((off_t)[attributes_file read:attributes_data size:[attributes_file length] error:error] < (off_t)[attributes_file length]) {
		free(attributes_data);
		attributes_data = NULL;
		[attributes_file release];
		return;
	}
	
	[attributes_file release];
	attributes_file = nil;
	
	mpq_attributes_header_t* attributes = (mpq_attributes_header_t*)attributes_data;
	[[self class] swap_uint32_array:(uint32_t*)attributes length:2];
	
	if (attributes->magic != ATTRIBUTES_MAGIC) {
		free(attributes_data);
		attributes_data = NULL;
		ReturnWithError(MPQErrorDomain, errInvalidAttributesFile, NULL, error)
	}
	
	ReturnWithNoError(error)
}

- (BOOL)_loadWithPath:(NSString*)path ignoreHeaderSizeField:(BOOL)ignoreHeaderSizeField error:(NSError**)error {
	// Copy the path argument
	archive_path = [path copy];

	// Are we going to be read-only?
	is_read_only = ![[NSFileManager defaultManager] isWritableFileAtPath:archive_path];
	
	int file_mode = 0;
	if (is_read_only) file_mode = O_RDONLY;
	else file_mode = O_RDWR;

	// Open the archive file
	archive_fd = open([archive_path fileSystemRepresentation], file_mode, 0644);
	if (archive_fd == -1) ReturnValueWithError(NO, NSPOSIXErrorDomain, errno, nil, error)

#if defined(__APPLE__)		
	// Turn off caching
	fcntl(archive_fd, F_NOCACHE, 1);
#endif

	// This function assumes that archive_offset has been initialized

	ssize_t bytes_read = 0;
	uint32_t i = 0;
	
	// Get the archive's size
	struct stat sb;
	if (fstat(archive_fd, &sb) == -1) ReturnValueWithError(NO, NSPOSIXErrorDomain, errno, nil, error)
	off_t file_size = sb.st_size;
	
	// If the file is too small to even be an MPQ archive, bail out
	if (file_size < 32) ReturnValueWithError(NO, MPQErrorDomain, errInvalidArchive, nil, error)
	
	// MPQ archives can be embedded in files, in which case the MPQ header must be 512 bytes aligned.
	do {
		bytes_read = pread(archive_fd, &header, sizeof(mpq_header_t), archive_offset);
		if (bytes_read == -1) ReturnValueWithPOSIXError(NO, nil, error)
		if ((size_t)bytes_read == 0) ReturnValueWithError(NO, MPQErrorDomain, errEndOfFile, nil, error)
		if ((size_t)bytes_read < sizeof(mpq_header_t)) ReturnValueWithError(NO, MPQErrorDomain, errIO, nil, error)
				
		// Byte swap the header
		[[self class] swap_mpq_header:&header];
		
		// Check the header
		if (header.mpq_magic == MPQ_MAGIC) {
			if (header.version == 0 && (header.header_size == sizeof(mpq_header_t) || ignoreHeaderSizeField)) break;
			if (header.version == 1 && (header.header_size == sizeof(mpq_header_t) + sizeof(mpq_extended_header_t) || ignoreHeaderSizeField)) break;
			ReturnValueWithError(NO, MPQErrorDomain, errInvalidArchive, nil, error)
		}
		
		// We may have read an MPQ shunt structure instead
		union _mpq_header_shunt_union {
			mpq_header_t* header;
			mpq_shunt_t* shunt;
		};
		union _mpq_header_shunt_union hsu;
		hsu.header = &header;
		mpq_shunt_t shunt = *hsu.shunt;
		
		// byte swap the shunt
		[[self class] swap_mpq_shunt:&shunt];
		
		// check the shunt
		if (shunt.shunt_magic == MPQ_SHUNT_MAGIC) {
			// Set the offset for the next iteration
			archive_offset = archive_offset + (off_t)(shunt.mpq_header_offset);
			continue;
		}
		
		// Move to the next possible offset
		archive_offset += 512;
	} while (1);
	
	// Version 1 archives have an extended header
	if (header.version == 1) {
		bytes_read = pread(archive_fd, &extended_header, sizeof(mpq_extended_header_t), archive_offset + sizeof(mpq_header_t));
		if (bytes_read == -1) ReturnValueWithPOSIXError(NO, nil, error)
		if ((size_t)bytes_read == 0) ReturnValueWithError(NO, MPQErrorDomain, errEndOfFile, nil, error)
		if ((size_t)bytes_read < sizeof(mpq_extended_header_t)) ReturnValueWithError(NO, MPQErrorDomain, errIO, nil, error)
		
		[[self class] swap_mpq_extended_header:&extended_header];
	} else {
		// Zero the version 1 extended header
		extended_header.hash_table_offset_high = 0;
		extended_header.block_table_offset_high = 0;
		extended_header.extended_block_offset_table_offset = 0;
	}
	
	// Pre-compute and cache the full sector size
	full_sector_size = MPQ_BASE_SECTOR_SIZE << header.sector_size_shift;
	
	// We've got all the information we need to allocate our memory
	if (![self allocateMemory]) ReturnValueWithError(NO, MPQErrorDomain, errOutOfMemory, nil, error)
	
	// Compute the size of the hash and block tables
	size_t hash_table_size = header.hash_table_length * sizeof(mpq_hash_table_entry_t);
	size_t block_table_size = header.block_table_length * sizeof(mpq_block_table_entry_t);
	
	// Compute final offsets for the hash and block tables
	hash_table_offset = header.hash_table_offset;
	block_table_offset = header.block_table_offset;
	if (header.version == 1) {
		hash_table_offset += ((off_t)(extended_header.hash_table_offset_high)) << 32;
		block_table_offset += ((off_t)(extended_header.block_table_offset_high)) << 32;
	}
	
	// Read the hash table
	bytes_read = pread(archive_fd, hash_table, hash_table_size, archive_offset + hash_table_offset);
	if (bytes_read == -1) ReturnValueWithPOSIXError(NO, nil, error)
	if ((size_t)bytes_read == 0) ReturnValueWithError(NO, MPQErrorDomain, errEndOfFile, nil, error)
	if ((size_t)bytes_read < hash_table_size) ReturnValueWithError(NO, MPQErrorDomain, errIO, nil, error)
	
	// Decrypt the hash table
	mpq_decrypt(hash_table, hash_table_size, mpq_hash_cstring(kHashTableEncryptionKey, HASH_KEY), NO);
	[self swap_hash_table];
	
	// Read the block table
	bytes_read = pread(archive_fd, block_table, block_table_size, archive_offset + block_table_offset);
	if (bytes_read == -1) ReturnValueWithPOSIXError(NO, nil, error)
	if ((size_t)bytes_read == 0) ReturnValueWithError(NO, MPQErrorDomain, errEndOfFile, nil, error)
	if ((size_t)bytes_read < block_table_size) ReturnValueWithError(NO, MPQErrorDomain, errIO, nil, error)
	
	// Decrypt the block table. Since it's really a uint32_t array, disable output swapping
	mpq_decrypt((char*)block_table, block_table_size, mpq_hash_cstring(kBlockTableEncryptionKey, HASH_KEY), YES);
	
	// Compute block_offset_table
	size_t extended_block_offset_table_size = header.block_table_length * sizeof(mpq_extended_block_offset_table_entry_t);
	if (extended_header.extended_block_offset_table_offset != 0) {
		mpq_extended_block_offset_table_entry_t* extended_block_offset_table = malloc(header.block_table_length * sizeof(mpq_extended_block_offset_table_entry_t));
		if (extended_block_offset_table == NULL) ReturnValueWithError(NO, MPQErrorDomain, errOutOfMemory, nil, error)
			
		// Read the extended block offset table
		bytes_read = pread(archive_fd, extended_block_offset_table, extended_block_offset_table_size, archive_offset + extended_header.extended_block_offset_table_offset);
		if (bytes_read == -1) {
			free(extended_block_offset_table);
			ReturnValueWithPOSIXError(NO, nil, error)
		}
		if ((size_t)bytes_read < extended_block_offset_table_size) {
			free(extended_block_offset_table);
			ReturnValueWithError(NO, MPQErrorDomain, errIO, nil, error)
		}
		
		// The extended block offset table is not encrypted, so we can just go on to byte swapping
		[self swap_extended_block_offset_table:extended_block_offset_table length:header.block_table_length];
		
		// Compute the block offset table
		for (i = 0; i < header.block_table_length; i++) block_offset_table[i] = (((off_t)(extended_block_offset_table[i].offset_high)) << 32) + block_table[i].offset;
		
		free(extended_block_offset_table);
	} else {
		// Simple copy of the offset field, extending it to 64 bits
		for (i = 0; i < header.block_table_length; i++) block_offset_table[i] = block_table[i].offset;
	}
	
	// We need to compute the archive's size, since that information is no longer valid in version 1 archives
	archive_size = 0;
	if (hash_table_offset > block_table_offset) archive_size = hash_table_offset + hash_table_size;
	else archive_size = block_table_offset + block_table_size;
	if (header.version == 1 && (off_t)(extended_header.extended_block_offset_table_offset + extended_block_offset_table_size) >= archive_size) {
		archive_size = extended_header.extended_block_offset_table_offset + extended_block_offset_table_size;
	}
	
	// If there's a file beyond the structural tables, refuse the archive
	for (i = 0; i < header.block_table_length; i++) if (block_offset_table[i] + block_table[i].archived_size >= archive_size) {
		ReturnValueWithError(NO, MPQErrorDomain, errInvalidArchive, nil, error)
	}
		
	// Do a consistency check on archive_size for version 0 archives
	if (header.version == 0 && header.archive_size != archive_size) ReturnValueWithError(NO, MPQErrorDomain, errInvalidArchive, nil, error)
	
	// Position the write offset at the beginning of the first structural table
	if (hash_table_offset < block_table_offset) archive_write_offset = hash_table_offset;
	else archive_write_offset = block_table_offset;
	if (header.version == 1 && (off_t)extended_header.extended_block_offset_table_offset < archive_write_offset)
		archive_write_offset = extended_header.extended_block_offset_table_offset;
	
	// mark the file count caches as dirty
	_fileCountCachesDirty = YES;
	
	// If the archive contains a weak signature, cache its block table entry
	uint32_t signature_hash_position = [self findHashPosition:kSignatureEncryptionKey locale:MPQNeutral error:NULL];
	if (signature_hash_position != 0xffffffff) {
		weak_signature_hash_entry = hash_table + signature_hash_position;
	} else weak_signature_hash_entry = NULL;
	
	// Check for a strong signature and cache it if it exists
	strong_signature = malloc(MPQ_STRONG_SIGNATURE_SIZE + 4);
	bytes_read = pread(archive_fd, strong_signature, MPQ_STRONG_SIGNATURE_SIZE + 4, archive_offset + archive_size);
	if (bytes_read == -1) ReturnValueWithPOSIXError(NO, nil, error)
	if (bytes_read < MPQ_STRONG_SIGNATURE_SIZE + 4) {
		free(strong_signature);
		strong_signature = NULL;
	} else {
		if (*(uint32_t*)strong_signature != MPQSwapInt32BigToHost(STRONG_SIGNATURE_MAGIC)) {
			free(strong_signature);
			strong_signature = NULL;
		}
	}
	
	// Load attributes if possible
	[self _loadAttributes:error];

	// We add the signature and attributes files to the list if they are in the MPQ
	if (![self _addListfileEntry:kSignatureFilename error:error]) return NO;
	if (![self _addListfileEntry:kAttributesFilename error:error]) return NO;
	if (![self _addListfileEntry:kListfileFilename error:error]) return NO;
	
	// The archive is not modified at this stage
	is_modified = NO;
	
	// Checked up and good to go
	ReturnValueWithNoError(YES, error)
}

#pragma mark init

+ (id)archiveWithFileLimit:(uint32_t)limit {
	return [self archiveWithFileLimit:limit error:(NSError**)NULL];
}

+ (id)archiveWithFileLimit:(uint32_t)limit error:(NSError**)error {
	return [[[self alloc] initWithFileLimit:limit error:error] autorelease];
}

+ (id)archiveWithPath:(NSString*)path {
	return [self archiveWithPath:path error:(NSError**)NULL];
}

+ (id)archiveWithPath:(NSString*)path error:(NSError**)error {
	return [[[self alloc] initWithPath:path error:error] autorelease];
}

+ (id)archiveWithAttributes:(NSDictionary*)attributes error:(NSError**)error {
	return [[[[self class] alloc] initWithAttributes:attributes error:error] autorelease];
}

- (void)commonInit {
	// Set the compressor to default compressor (zlib)
	default_compressor = MPQZLIBCompression;
	
	// We'll keep track of the number of files open
	open_file_count = 0;
	
	// By default, we keep track of the listfile
	save_listfile = YES;
	
	// No delegate initially
	delegate = nil;
	
	// No operations initially
	last_operation = NULL;
	deferred_operations_count = 0;
	
	// No attributes initially
	attributes_data = NULL;
	attributes_data_size = 0;
}

- (id)init {
	[self autorelease];
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

- (id)initWithAttributes:(NSDictionary*)attributes error:(NSError**)error {
	NSParameterAssert(attributes != nil);
	
	NSNumber* temp;
	
	self = [super init];
	if (!self) return nil;
	
	NSAutoreleasePool* p = [NSAutoreleasePool new];
	[self commonInit];
	
	NSString* path = [attributes objectForKey:MPQArchivePath];
	if (path) {
		// MPQArchiveOffset
		archive_offset = 0;
		temp = [attributes objectForKey:MPQArchiveOffset];
		if (temp) archive_offset = [temp longLongValue];
		if (archive_offset < 0 || archive_offset % 512 != 0) {
			[p release];
			ReturnFromInitWithError(MPQErrorDomain, errInvalidArchiveOffset, nil, error)
		}
		
		// MPQIgnoreHeaderSizeField
		BOOL ignoreHeaderSizeField = NO;
		temp = [attributes objectForKey:MPQIgnoreHeaderSizeField];
		if (temp) ignoreHeaderSizeField = [temp boolValue];
		
		// load the archive from the provided path
		if (![self _loadWithPath:path ignoreHeaderSizeField:ignoreHeaderSizeField error:error]) {
			MPQTransferErrorAndDrainPool(error, p);
			[self release];
			return nil;
		}
	} else {
		// MPQArchiveVersion
		MPQVersion version = MPQOriginalVersion;
		temp = [attributes objectForKey:MPQArchiveVersion];
		if (temp) version = [temp unsignedShortValue];
		if (version != MPQOriginalVersion && version != MPQExtendedVersion) {
			[p release];
			ReturnFromInitWithError(MPQErrorDomain, errInvalidArchiveVersion, nil, error)
		}
		
		// MPQMaximumNumberOfFiles
		uint32_t limit = 1024;
		temp = [attributes objectForKey:MPQMaximumNumberOfFiles];
		if (temp) limit = [temp unsignedIntValue];
		
		// MPQArchiveOffset
		off_t offset = 0;
		temp = [attributes objectForKey:MPQArchiveOffset];
		if (temp) offset = [temp longLongValue];
		if (offset < 0 || offset % 512 != 0) {
			[p release];
			ReturnFromInitWithError(MPQErrorDomain, errInvalidArchiveOffset, nil, error)
		}
		
		// create a new archive with the provided file limit, version and offset
		if (![self _createNewArchive:limit version:version offset:offset error:error]) {
			MPQTransferErrorAndDrainPool(error, p);
			[self release];
			return nil;
		}
	}
	
	[p release];
	ReturnValueWithNoError(self, error)
}

- (id)initWithFileLimit:(uint32_t)limit {
	return [self initWithFileLimit:limit error:(NSError**)NULL];
}

- (id)initWithFileLimit:(uint32_t)limit error:(NSError**)error {
	return [self initWithAttributes:[NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:limit] forKey:MPQMaximumNumberOfFiles] error:error];
}

- (id)initWithPath:(NSString*)path {
	return [self initWithPath:path error:(NSError**)NULL];
}

- (id)initWithPath:(NSString*)path error:(NSError**)error {
	return [self initWithAttributes:[NSDictionary dictionaryWithObject:path forKey:MPQArchivePath] error:error];
}

- (void)dealloc {
	[self freeMemory];
	
	// freeMemory only handles what allocateMemory allocated
	if (strong_signature) free(strong_signature);
	
	[archive_path release];
	archive_path = nil;
	
	if (attributes_data) free(attributes_data);
	attributes_data = NULL;
	
	// Close the archive if it's open
	if (archive_fd != -1) close(archive_fd);
	
	// Sayonara
	[super dealloc];
}

- (NSString*)description {
	return [[self archiveInfo] description];
}

#pragma mark delegate

- (id)delegate {
	return delegate;
}

- (void)setDelegate:(id)anObject {
	delegate = anObject;
}

#pragma mark archive info

- (NSDictionary*)archiveInfo {
	return [NSDictionary dictionaryWithObjectsAndKeys:
		[NSNumber numberWithUnsignedLongLong:archive_size], MPQArchiveSize,
		[NSNumber numberWithUnsignedInt:header.sector_size_shift], MPQSectorSizeShift,
		[NSNumber numberWithUnsignedInt:[self fileCount]], MPQNumberOfFiles,
		[NSNumber numberWithUnsignedInt:[self maximumNumberOfFiles]], MPQMaximumNumberOfFiles,
		[NSNumber numberWithUnsignedInt:[self validFileCount]], MPQNumberOfValidFiles,
		[NSNumber numberWithLongLong:archive_offset], MPQArchiveOffset,
		[NSNumber numberWithUnsignedShort:header.version], MPQArchiveVersion,
		[NSNumber numberWithUnsignedLongLong:hash_table_offset], @"MPQArchiveHashTableOffset",
		[NSNumber numberWithUnsignedLongLong:block_table_offset], @"MPQArchiveBlockTableOffset",
		archive_path, MPQArchivePath,
		nil];
}

- (NSString*)path {
	return archive_path;
}

- (BOOL)modified {
	return is_modified;
}

- (BOOL)readOnly {
	return is_read_only;
}

- (uint32_t)openFileCount {
	return open_file_count;
}

- (uint32_t)fileCount {
	if (_fileCountCachesDirty) [self _updateFileCountCaches];
	return _fileCountCache;
}

- (uint32_t)validFileCount {
	if (_fileCountCachesDirty) [self _updateFileCountCaches];
	return _validFileCountCache;
}

- (uint32_t)maximumNumberOfFiles {
	return header.hash_table_length;
}

- (uint32_t)openFileCountWithPosition:(uint32_t)position {
	return open_file_count_table[position];
}

#pragma mark operations

- (uint32_t)operationCount {
	return deferred_operations_count;
}

- (BOOL)undoLastOperation:(NSError**)error {	 
	if (deferred_operations_count == 0) ReturnValueWithNoError(YES, error)
	mpq_deferred_operation_t* operation = last_operation;
	
	// Can't undo a file addition operation if the file is open
	if (operation->type == MPQDOAdd && open_file_count_table[operation->primary_file_context.hash_position] != 0) ReturnValueWithError(NO, MPQErrorDomain, errFileIsOpen, nil, error)
	
	// Bail out if we need to restore a filename and we can't do the ASCII convertion
	char* filename_cstring = NULL;
	if (operation->primary_file_context.filename) {
		filename_cstring = _MPQCreateASCIIFilename(operation->primary_file_context.filename, error);
		if (!filename_cstring) return NO;
	}
	
	// Invalidate the encryption key, sector table and filename caches
	encryption_keys_cache[operation->primary_file_context.hash_position] = 0;
	if (sector_tables_cache[operation->primary_file_context.hash_position]) free(sector_tables_cache[operation->primary_file_context.hash_position]);
	sector_tables_cache[operation->primary_file_context.hash_position] = NULL;
	if (filename_table[operation->primary_file_context.hash_position]) free(filename_table[operation->primary_file_context.hash_position]);
		
	// Restore archive state
	block_table[hash_table[operation->primary_file_context.hash_position].block_table_index] = operation->primary_file_context.block_entry;
	block_offset_table[hash_table[operation->primary_file_context.hash_position].block_table_index] = operation->primary_file_context.block_offset;
	hash_table[operation->primary_file_context.hash_position] = operation->primary_file_context.hash_entry;
	filename_table[operation->primary_file_context.hash_position] = filename_cstring;
	
	// Delete the operation
	[self _flushLastDO];
	if (deferred_operations_count == 0 && archive_path != nil) is_modified = NO;
	
	ReturnValueWithNoError(YES, error)
}

#pragma mark digital signing

- (NSData*)computeWeakSignatureDigest:(NSError**)error {
	int perr = 0;
	int stage = 0;
	
	// If the archive is not weakly signed, we return NO
	if (!weak_signature_hash_entry) ReturnValueWithError(NO, MPQErrorDomain, errNoSignature, nil, error)
	mpq_block_table_entry_t* weak_signature_block_entry = block_table + weak_signature_hash_entry->block_table_index;
	
	// If the archive doesn't exist on disk yet, return nil
	if (!archive_path) ReturnValueWithError(nil, MPQErrorDomain, errNoArchiveFile, nil, error)
	
	// Prepare the new digest context and buffer
	MD5_CTX ctx;
	MD5_Init(&ctx);
	void* digest = malloc(MD5_DIGEST_LENGTH);
	if (!digest) ReturnValueWithError(nil, MPQErrorDomain, errOutOfMemory, nil, error)
	
	// 1024 times 4096 bytes, 2 times
	void* io_buffer = valloc(0x800000);
	void* io_buffers[2] = {io_buffer, BUFFER_OFFSET(io_buffer, 0x400000)};
	
	// This is the total number of bytes that we need to read from the archive file
	off_t total_bytes_to_read = block_offset_table[weak_signature_hash_entry->block_table_index];
	
	// We have to keep track of aiocb offsets manually, since the OS may change the value in the aiocbs under us
	off_t iocb_offsets[2] = {archive_offset, archive_offset + 0x400000};
	
	// Prepare 2 aio control buffers
#if defined(MPQKIT_USE_AIO)
	struct aiocb iocb_buffer[2];
	struct aiocb* iocbs[2] = {iocb_buffer, iocb_buffer + 1};
	bzero(iocbs[0], sizeof(struct aiocb));
	bzero(iocbs[1], sizeof(struct aiocb));
	
	iocbs[0]->aio_fildes = archive_fd;
	iocbs[0]->aio_buf = io_buffers[0];
	iocbs[0]->aio_offset = iocb_offsets[0];
	iocbs[0]->aio_nbytes = 0x400000;
	iocbs[0]->aio_lio_opcode = LIO_READ;
	
	iocbs[1]->aio_fildes = archive_fd;
	iocbs[1]->aio_buf = io_buffers[1];
	iocbs[1]->aio_offset = iocb_offsets[1];
	iocbs[1]->aio_nbytes = 0x400000;
	iocbs[1]->aio_lio_opcode = LIO_READ;
	
	// Send the aio control buffers to the kernel
	do {
		if (archive_offset + total_bytes_to_read <= iocb_offsets[1]) perr = aio_read(iocbs[0]);
		else perr = lio_listio(LIO_NOWAIT, iocbs, 2, NULL);
		if (perr == -1 && errno != EAGAIN) {
			if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
			goto AbortDigest;
		}
	} while (perr == -1 && errno == EAGAIN);
#endif
	
	// This will keep track of which aiocb we're going to read from (and suspend on) next
	uint8_t current_iocb = 0;
	
	// Loop until we have read everything
	while(total_bytes_to_read > 0) {
#if defined(MPQKIT_USE_AIO)
		// Suspend until current_iocb is done
		aio_suspend((const struct aiocb**)(iocbs + current_iocb), 1, NULL);
		
		// Get result from iocbs[current_iocb]
		perr = aio_error(iocbs[current_iocb]);
		stage = 1;
		if (perr == EINPROGRESS) continue;
		if (perr) {
			if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:perr userInfo:nil];
			goto AbortDigest;
		}
		
		// This completes the aio command
		ssize_t bytes_read = aio_return(iocbs[current_iocb]);
#else		 
		ssize_t bytes_read = pread(archive_fd, io_buffers[current_iocb], 0x400000, iocb_offsets[current_iocb]);
		if (bytes_read == -1) {
			perr = -1;
			if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
			goto AbortDigest;
		} else if (bytes_read == 0) {
			if (error) *error = [MPQError errorWithDomain:MPQErrorDomain code:errEndOfFile userInfo:nil];
			goto AbortDigest;
		}
#endif
		
		// Need to correct the amount of bytes read if we went too far
		if ((off_t)bytes_read > total_bytes_to_read) bytes_read = (ssize_t)total_bytes_to_read;
		
		// Update the digest
		MD5_Update(&ctx, (const void*)(io_buffers[current_iocb]), bytes_read);
		
		// Update bytes to read
		total_bytes_to_read -= bytes_read;
		if (total_bytes_to_read == 0) break;
		
		// Prepare the next read
		iocb_offsets[current_iocb] = iocb_offsets[(current_iocb + 1) % 2] + 0x400000;
		
#if defined(MPQKIT_USE_AIO)
		bzero(iocbs[current_iocb], sizeof(struct aiocb));
		iocbs[current_iocb]->aio_fildes = archive_fd;
		iocbs[current_iocb]->aio_buf = io_buffers[current_iocb];
		iocbs[current_iocb]->aio_nbytes = 0x400000;
		iocbs[current_iocb]->aio_offset = iocb_offsets[current_iocb];
		
		perr = aio_read(iocbs[current_iocb]);
		stage = 2;
		if (perr) {
			if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:perr userInfo:nil];
			goto AbortDigest;
		}
#endif
		
		// Update current aiocb
		current_iocb = (current_iocb + 1) % 2;
	}
	
	// Inject 0s in place of (signature)
	// TODO: use static const pre-made buffer for this instead, signature is fixed length
	char zero = 0;
	uint32_t i = 0;
	for(; i < weak_signature_block_entry->archived_size; i++) MD5_Update(&ctx, &zero, 1);
	
	// Update the offsets
	iocb_offsets[0] = archive_offset + block_offset_table[weak_signature_hash_entry->block_table_index] + weak_signature_block_entry->archived_size;
	iocb_offsets[1] = iocb_offsets[0] + 0x400000;
	
	// Update the number of bytes to read
	total_bytes_to_read = archive_offset + archive_size - iocb_offsets[0];
	
	// Cancel whatever IO may still be running
	stage = 3;
	
#if defined(MPQKIT_USE_AIO)
	perr = AIO_NOTCANCELED;
	while(perr == AIO_NOTCANCELED) {
		perr = aio_cancel(archive_fd, iocbs[0]);
		if (perr == AIO_ALLDONE) aio_return(iocbs[0]);
	}
	
	perr = AIO_NOTCANCELED;
	while(perr == AIO_NOTCANCELED) {
		perr = aio_cancel(archive_fd, iocbs[1]);
		if (perr == AIO_ALLDONE) aio_return(iocbs[1]);
	}
	
	// Prepare the 2 aiocbs for post-signature digesting
	bzero(iocbs[0], sizeof(struct aiocb));
	bzero(iocbs[1], sizeof(struct aiocb));
	
	iocbs[0]->aio_fildes = archive_fd;
	iocbs[0]->aio_buf = io_buffers[current_iocb];
	iocbs[0]->aio_offset = iocb_offsets[0];
	iocbs[0]->aio_nbytes = 0x400000;
	iocbs[0]->aio_lio_opcode = LIO_READ;
	
	iocbs[1]->aio_fildes = archive_fd;
	iocbs[1]->aio_buf = io_buffers[current_iocb];
	iocbs[1]->aio_offset = iocb_offsets[1];
	iocbs[1]->aio_nbytes = 0x400000;
	iocbs[1]->aio_lio_opcode = LIO_READ;
	
	// Send the aio control buffers to the kernel
	stage = 4;
	do {
		if (archive_offset + archive_size <= iocb_offsets[1]) perr = aio_read(iocbs[0]);
		else perr = lio_listio(LIO_NOWAIT, iocbs, 2, NULL);
		if (perr == -1 && errno != EAGAIN) {
			if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
			goto AbortDigest;
		}
	} while (perr == -1 && errno == EAGAIN);
#endif
	
	// Loop until we have read everything
	current_iocb = 0;
	while(total_bytes_to_read > 0) {
#if defined(MPQKIT_USE_AIO)
		// Suspend until current_iocb is done
		aio_suspend((const struct aiocb**)(iocbs + current_iocb), 1, NULL);
		
		// Get result from iocbs[current_iocb]
		perr = aio_error(iocbs[current_iocb]);
		stage = 5;
		if (perr == EINPROGRESS) continue;
		if (perr) {
			if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:perr userInfo:nil];
			goto AbortDigest;
		}
		
		// This completes the aio command
		ssize_t bytes_read = aio_return(iocbs[current_iocb]);
#else
		ssize_t bytes_read = pread(archive_fd, io_buffers[current_iocb], 0x400000, iocb_offsets[current_iocb]);
		if (bytes_read == -1) {
			perr = -1;
			if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
			goto AbortDigest;
		} else if (bytes_read == 0) {
			if (error) *error = [MPQError errorWithDomain:MPQErrorDomain code:errEndOfFile userInfo:nil];
			goto AbortDigest;
		}
#endif
		
		// Need to correct the amount of bytes read if we went too far
		if ((off_t)bytes_read > total_bytes_to_read) bytes_read = (ssize_t)total_bytes_to_read;
		
		// Update the digest
		MD5_Update(&ctx, (const void*)io_buffers[current_iocb], bytes_read);
		
		// Update bytes to read
		total_bytes_to_read -= bytes_read;
		if (total_bytes_to_read == 0) break;
		
		// Prepare the next read
		iocb_offsets[current_iocb] = iocb_offsets[(current_iocb + 1) % 2] + 0x400000;
		
#if defined(MPQKIT_USE_AIO)
		bzero(iocbs[current_iocb], sizeof(struct aiocb));
		iocbs[current_iocb]->aio_fildes = archive_fd;
		iocbs[current_iocb]->aio_buf = io_buffers[current_iocb];
		iocbs[current_iocb]->aio_nbytes = 0x400000;
		iocbs[current_iocb]->aio_offset = iocb_offsets[current_iocb];
		iocbs[current_iocb]->aio_lio_opcode = LIO_READ;
		
		perr = aio_read(iocbs[current_iocb]);
		stage = 6;
		if (perr) {
			if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:perr userInfo:nil];
			goto AbortDigest;
		}
#endif
		
		// Update current aiocb
		current_iocb = (current_iocb + 1) % 2;
	}
	
#if defined(MPQKIT_USE_AIO)
	// Cancel whatever IO may still be running
	perr = AIO_NOTCANCELED;
	while(perr == AIO_NOTCANCELED) {
		perr = aio_cancel(archive_fd, iocbs[0]);
		if (perr == AIO_ALLDONE) aio_return(iocbs[0]);
	}
	
	perr = AIO_NOTCANCELED;
	while(perr == AIO_NOTCANCELED) {
		perr = aio_cancel(archive_fd, iocbs[1]);
		if (perr == AIO_ALLDONE) aio_return(iocbs[1]);
	}
#endif
	
	// Finalize the digest
	MD5_Final(digest, &ctx);
	
	// Clean up and return
	free(io_buffer);
	ReturnValueWithNoError([[NSData alloc] initWithBytesNoCopy:digest length:MD5_DIGEST_LENGTH freeWhenDone:YES], error)
	
AbortDigest:
	MPQDebugLog(@"perr %d occured at stage %d with total_bytes_to_read at %ld in computeWeakSignatureDigest", perr, stage, total_bytes_to_read);
	if (perr == -1) MPQDebugLog(@"errno is %d", errno);
	
#if defined(MPQKIT_USE_AIO)
	// Cancel whatever IO may still be running
	perr = AIO_NOTCANCELED;
	while(perr == AIO_NOTCANCELED) {
		perr = aio_cancel(archive_fd, iocbs[0]);
		if (perr == AIO_ALLDONE) aio_return(iocbs[0]);
	}
	
	perr = AIO_NOTCANCELED;
	while(perr == AIO_NOTCANCELED) {
		perr = aio_cancel(archive_fd, iocbs[1]);
		if (perr == AIO_ALLDONE) aio_return(iocbs[1]);
	}
#endif
	
	free(io_buffer);
	free(digest);
	return nil;
}

- (BOOL)verifyBlizzardWeakSignature:(BOOL*)isSigned error:(NSError**)error {
	// If the archive is not weakly signed, we return NO
	if (!weak_signature_hash_entry) ReturnValueWithError(NO, MPQErrorDomain, errNoSignature, nil, error)
	
	// Get the weak signature and weak digest
	NSData* signature = [self copyDataForFile:kSignatureFilename error:error];
	if (!signature) return NO;
	
	NSData* digest = [self computeWeakSignatureDigest:error];
	if (!digest) return NO;
	
	// Verify it
	int result = mpq_verify_weak_signature(blizzard_weak_public_rsa, [signature bytes], [digest bytes]);
	
	// Clean up
	[signature release];
	[digest release];
	
	if (result == 1) ReturnValueWithNoError(YES, error)
	ReturnValueWithNoError(NO, error)
}

- (NSData*)computeStrongSignatureDigestFrom:(off_t)digestOffset size:(off_t)digestSize tail:(NSData*)digestTail error:(NSError**)error {
	int perr = 0;
	int stage = 0;
	
	// If the archive doesn't exist on disk yet, return nil
	if (!archive_path) ReturnValueWithError(nil, MPQErrorDomain, errNoArchiveFile, nil, error)
	
	// Prepare the new digest context and buffer
	SHA_CTX ctx;
	SHA1_Init(&ctx);
	void* digest = malloc(SHA_DIGEST_LENGTH);
	
	// 1024 times 4096 bytes, 2 times
	void* io_buffer = valloc(0x800000);
	void* io_buffers[2] = {io_buffer, BUFFER_OFFSET(io_buffer, 0x400000)};
	
	// This is the total number of bytes that we need to read from the archive file
	off_t total_bytes_to_read = digestSize;
	
	// We have to keep track of aiocb offsets manually, since the OS may change the value in the aiocbs under us
	off_t iocb_offsets[2] = {digestOffset, digestOffset + 0x400000};
	
#if defined(MPQKIT_USE_AIO)
	// Prepare 2 aio control buffers
	struct aiocb iocb_buffer[2];
	struct aiocb* iocbs[2] = {iocb_buffer, iocb_buffer + 1};
	bzero(iocbs[0], sizeof(struct aiocb));
	bzero(iocbs[1], sizeof(struct aiocb));
	
	iocbs[0]->aio_fildes = archive_fd;
	iocbs[0]->aio_buf = io_buffers[0];
	iocbs[0]->aio_offset = iocb_offsets[0];
	iocbs[0]->aio_nbytes = 0x400000;
	iocbs[0]->aio_lio_opcode = LIO_READ;
	
	iocbs[1]->aio_fildes = archive_fd;
	iocbs[1]->aio_buf = io_buffers[1];
	iocbs[1]->aio_offset = iocb_offsets[1];
	iocbs[1]->aio_nbytes = 0x400000;
	iocbs[1]->aio_lio_opcode = LIO_READ;
	
	// Send the aio control buffers to the kernel
	do {
		if (digestOffset + total_bytes_to_read <= iocb_offsets[1]) perr = aio_read(iocbs[0]);
		else perr = lio_listio(LIO_NOWAIT, iocbs, 2, NULL);
		if (perr == -1 && errno != EAGAIN) {
			if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
			goto AbortDigest;
		}
	} while (perr == -1 && errno == EAGAIN);
#endif
	
	// This will keep track of which aiocb we're going to read from (and suspend on) next
	uint8_t current_iocb = 0;
	
	// Loop until we have read everything
	while(total_bytes_to_read > 0) {
#if defined(MPQKIT_USE_AIO)
		// Suspend until current_iocb is done
		aio_suspend((const struct aiocb**)(iocbs + current_iocb), 1, NULL);
		
		// Get result from iocbs[current_iocb]
		perr = aio_error(iocbs[current_iocb]);
		stage = 1;
		if (perr == EINPROGRESS) continue;
		if (perr) {
			if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:perr userInfo:nil];
			goto AbortDigest;
		}
		
		// This completes the aio command
		ssize_t bytes_read = aio_return(iocbs[current_iocb]);
#else
		ssize_t bytes_read = pread(archive_fd, io_buffers[current_iocb], 0x400000, iocb_offsets[current_iocb]);
		if (bytes_read == -1) {
			perr = -1;
			if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
			goto AbortDigest;
		} else if (bytes_read == 0) {
			if (error) *error = [MPQError errorWithDomain:MPQErrorDomain code:errEndOfFile userInfo:nil];
			goto AbortDigest;
		}
#endif
		
		// Need to correct the amount of bytes read if we went too far
		if ((off_t)bytes_read > total_bytes_to_read) bytes_read = (ssize_t)total_bytes_to_read;
		
		// Update the digest
		SHA1_Update(&ctx, (const void*)io_buffers[current_iocb], bytes_read);
		
		// Update bytes to read
		total_bytes_to_read -= bytes_read;
		if (total_bytes_to_read == 0) break;
		
		// Prepare the next read
		iocb_offsets[current_iocb] = iocb_offsets[(current_iocb + 1) % 2] + 0x400000;
		
#if defined(MPQKIT_USE_AIO)
		bzero(iocbs[current_iocb], sizeof(struct aiocb));
		iocbs[current_iocb]->aio_fildes = archive_fd;
		iocbs[current_iocb]->aio_buf = io_buffers[current_iocb];
		iocbs[current_iocb]->aio_nbytes = 0x400000;
		iocbs[current_iocb]->aio_offset = iocb_offsets[current_iocb];
		
		perr = aio_read(iocbs[current_iocb]);
		stage = 2;
		if (perr) {
			if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:perr userInfo:nil];
			goto AbortDigest;
		}
#endif
		
		// Update current aiocb
		current_iocb = (current_iocb + 1) % 2;
	}
	
#if defined(MPQKIT_USE_AIO)
	// Cancel whatever IO may still be running
	perr = AIO_NOTCANCELED;
	while(perr == AIO_NOTCANCELED) {
		perr = aio_cancel(archive_fd, iocbs[0]);
		if (perr == AIO_ALLDONE) aio_return(iocbs[0]);
	}
	
	perr = AIO_NOTCANCELED;
	while(perr == AIO_NOTCANCELED) {
		perr = aio_cancel(archive_fd, iocbs[1]);
		if (perr == AIO_ALLDONE) aio_return(iocbs[1]);
	}
#endif
	
	// Update the hash with the tail, if there is one
	if (digestTail) SHA1_Update(&ctx, [digestTail bytes], [digestTail length]);
	
	// Finalize the digest
	SHA1_Final(digest, &ctx);
	
	// Clean up and return
	free(io_buffer);
	ReturnValueWithNoError([[NSData alloc] initWithBytesNoCopy:digest length:SHA_DIGEST_LENGTH freeWhenDone:YES], error)
	
AbortDigest:
	MPQDebugLog(@"perr %d occured at stage %d with total_bytes_to_read at %ld in computeStrongSignatureDigest", perr, stage, total_bytes_to_read);
	if (perr == -1) MPQDebugLog(@"errno is %d", errno);
	
#if defined(MPQKIT_USE_AIO)
	// Cancel whatever IO may still be running
	perr = AIO_NOTCANCELED;
	while(perr == AIO_NOTCANCELED) {
		perr = aio_cancel(archive_fd, iocbs[0]);
		if (perr == AIO_ALLDONE) aio_return(iocbs[0]);
	}
	
	perr = AIO_NOTCANCELED;
	while(perr == AIO_NOTCANCELED) {
		perr = aio_cancel(archive_fd, iocbs[1]);
		if (perr == AIO_ALLDONE) aio_return(iocbs[1]);
	}
#endif
	
	free(io_buffer);
	free(digest);
	return nil;
}

- (BOOL)hasStrongSignature {
	if (!strong_signature) return NO;
	return YES;
}

- (BOOL)verifyStrongSignatureWithKey:(RSA*)key digest:(NSData*)digest error:(NSError**)error {
	// If the archive is not strongly signed, we return NO
	if (!strong_signature) ReturnValueWithError(NO, MPQErrorDomain, errNoSignature, nil, error)
	
	// Verify it
	int result = mpq_verify_strong_signature(key, strong_signature, [digest bytes]);
	
	if (result == 1) ReturnValueWithNoError(YES, error)
	ReturnValueWithNoError(NO, error)
}

- (BOOL)verifyBlizzardStrongSignature:(NSError**)error {
	// If the archive is not strongly signed, we return NO
	if (!strong_signature) ReturnValueWithError(NO, MPQErrorDomain, errNoSignature, nil, error)
	
	// Get the strong digest
	NSData* digest = [self computeStrongSignatureDigestFrom:archive_offset size:archive_size tail:nil error:error];
	if (!digest) return NO;
	
	BOOL result = [self verifyStrongSignatureWithKey:blizzard_strong_public_rsa digest:digest error:error];
	[digest release];
	return result;
}

- (BOOL)verifyWoWSurveySignature:(NSError**)error {
	// If the archive is not strongly signed, we return NO
	if (!strong_signature) ReturnValueWithError(NO, MPQErrorDomain, errNoSignature, nil, error)
		
	// Get the strong digest
	NSData* digest = [self computeStrongSignatureDigestFrom:archive_offset size:archive_size tail:[@"ARCHIVE" dataUsingEncoding:NSASCIIStringEncoding] error:error];
	if (!digest) return NO;
	
	BOOL result = [self verifyStrongSignatureWithKey:wow_survey_public_rsa digest:digest error:error];
	[digest release];
	return result;
}

- (BOOL)verifyWoWMacPatchSignature:(NSError**)error {
	// If the archive is not strongly signed, we return NO
	if (!strong_signature) ReturnValueWithError(NO, MPQErrorDomain, errNoSignature, nil, error)
	
	// Get the strong digest
	NSData* digest = [self computeStrongSignatureDigestFrom:archive_offset size:archive_size tail:[@"ARCHIVE" dataUsingEncoding:NSASCIIStringEncoding] error:error];
	if (!digest) return NO;
	
	BOOL result = [self verifyStrongSignatureWithKey:wow_mac_patch_public_rsa digest:digest error:error];
	[digest release];
	return result;
}

- (BOOL)verifyWarcraft3MapSignature:(NSError**)error {
	// If the archive is not strongly signed, we return NO
	if (!strong_signature) ReturnValueWithError(NO, MPQErrorDomain, errNoSignature, nil, error)
	
	// The signature of a Warcraft 3 map includes at the end the map's capitalized filename
	NSString* capitalizedFilename = [[archive_path lastPathComponent] uppercaseString];
	
	// Get the strong digest
	NSData* digest = [self computeStrongSignatureDigestFrom:0 size:(archive_offset + archive_size) tail:[capitalizedFilename dataUsingEncoding:NSUTF8StringEncoding] error:error];
	if (!digest) return NO;
	
	BOOL result = [self verifyStrongSignatureWithKey:warcraft3_map_public_rsa digest:digest error:error];
	[digest release];
	return result;
}

- (BOOL)verifyStarcraftMapSignature:(NSError**)error {
	// If the archive is not strongly signed, we return NO
	if (!strong_signature) ReturnValueWithError(NO, MPQErrorDomain, errNoSignature, nil, error)
	
	// The signature of a Starcraft map includes at the end the map's capitalized filename
	NSString* capitalizedFilename = [[archive_path lastPathComponent] uppercaseString];
	
	// Get the strong digest
	NSData* digest = [self computeStrongSignatureDigestFrom:0 size:(archive_offset + archive_size) tail:[capitalizedFilename dataUsingEncoding:NSUTF8StringEncoding] error:error];
	if (!digest) return NO;
	
	BOOL result = [self verifyStrongSignatureWithKey:starcraft_map_public_rsa digest:digest error:error];
	[digest release];
	return result;
}

#pragma mark options

- (BOOL)storesListfile {
	return save_listfile;
}

- (void)setStoresListfile:(BOOL)store {
	save_listfile = store;
	return;
}

- (MPQCompressorFlag)defaultCompressor {
	return default_compressor;
}

- (BOOL)setDefaultCompressor:(MPQCompressorFlag)compressor {
	// Can't set compressor to non-existant compressor
	if ((compressor & ~MPQCompressorMask)) return NO;
	
	// Can't set the default compressor to ADPCM
	if ((compressor & (MPQMonoADPCMCompression | MPQStereoADPCMCompression))) return NO;
	
	default_compressor = compressor;
	return YES;
}

#pragma mark file list

- (BOOL)loadInternalListfile:(NSError**)error {
	NSAutoreleasePool* p = [NSAutoreleasePool new];
	BOOL result = NO;
	
	// Try to open the listfile
	NSData* listfile_data = [self copyDataForFile:kListfileFilename locale:MPQNeutral error:error];
	if (!listfile_data) {
		MPQTransferErrorAndDrainPool(error, p);
		return NO;
	}
	
	// Is it big enough to contain anything useful?
	if ([listfile_data length] > 0) {
		NSArray* listfileArray = [NSArray arrayWithListfileData:listfile_data];
		result = [self addArrayToFileList:listfileArray error:error];
	}
	
	[listfile_data release];
	MPQTransferErrorAndDrainPool(error, p);
	ReturnValueWithNoError(result, error)
}

- (BOOL)addArrayToFileList:(NSArray*)listfile {
	return [self addArrayToFileList:listfile error:(NSError**)NULL];
}

- (BOOL)addArrayToFileList:(NSArray*)listfile error:(NSError**)error {
	NSParameterAssert(listfile != nil);
	NSAutoreleasePool* p = [NSAutoreleasePool new];
	
	// Add every entry in the listfile
	NSEnumerator* listfileEnumerator = [listfile objectEnumerator];
	NSString* listfileEntry = nil;
	
	while ((listfileEntry = [listfileEnumerator nextObject])) {
	  if (![listfileEntry isEqualToString:@""]) {
		BOOL result = [self _addListfileEntry:listfileEntry error:error];
		if (!result) {
			MPQTransferErrorAndDrainPool(error, p);
			return NO;
		}
	  }
	}
	
	[p release];
	ReturnValueWithNoError(YES, error)
}

- (BOOL)addContentsOfFileToFileList:(NSString*)path {
	return [self addContentsOfFileToFileList:path error:(NSError**)NULL];
}

- (BOOL)addContentsOfFileToFileList:(NSString*)path error:(NSError**)error {
	NSParameterAssert(path != nil);
	NSAutoreleasePool* p = [NSAutoreleasePool new];

#if defined(__APPLE__)
	NSData* fileData = [NSData dataWithContentsOfFile:path options:NSUncachedRead error:error];
#elif defined(GNUSTEP)
	NSData* fileData = [NSData dataWithContentsOfFile:path];
#endif
	if (!fileData) {
#if defined(GNUSTEP)
		if (error) *error = [NSError _last];
#endif
		MPQTransferErrorAndDrainPool(error, p);
		return NO;
	}
	
	BOOL result = [self addArrayToFileList:[NSArray arrayWithListfileData:fileData] error:error];
	
	MPQTransferErrorAndDrainPool(error, p);
	return result;
}

- (NSArray*)fileList; {
	// Make a new NSMutableArray to set things up
	NSMutableArray* tempArray = [NSMutableArray arrayWithCapacity:header.hash_table_length];

	// Look through the name table and add all the entries to the array
	uint32_t current_file_index = 0;
	for (; current_file_index < header.hash_table_length; current_file_index++) {
		if (filename_table[current_file_index]) {
			[tempArray addObject:[NSString stringWithCString:(filename_table[current_file_index]) encoding:NSASCIIStringEncoding]];
		}
	}
	return tempArray;
}

#pragma mark file info

- (NSEnumerator*)fileInfoEnumerator {
	return [_MPQFileInfoEnumerator enumeratorWithArchive:self];
}

- (NSDictionary*)_nextFileInfo:(uint32_t*)hash_position {
	NSParameterAssert(hash_position != NULL);
	NSDictionary* tempDict = nil;
	
	// The plan is simple: iterate through the hash table
	while ((*hash_position < header.hash_table_length) && !tempDict) {
		tempDict = [self fileInfoForPosition:*hash_position];
		(*hash_position)++;
	}
	
	return tempDict;
}

- (NSDictionary*)fileInfoForPosition:(uint32_t)hash_position {
	return [self fileInfoForPosition:hash_position error:(NSError**)NULL];
}

- (NSDictionary*)fileInfoForPosition:(uint32_t)hash_position error:(NSError**)error {
	NSParameterAssert(hash_position < header.hash_table_length);
	
	// If the file is invalid, we can't delete it
	mpq_hash_table_entry_t* hash_entry = hash_table + hash_position;
	if (hash_entry->block_table_index == HASH_TABLE_DELETED) ReturnValueWithError(nil, MPQErrorDomain, errFileIsDeleted, nil, error)
	if (hash_entry->block_table_index == HASH_TABLE_EMPTY) ReturnValueWithError(nil, MPQErrorDomain, errHashTableEntryNotFound, nil, error)
	
	mpq_block_table_entry_t* block_entry = block_table + hash_entry->block_table_index;
	if (!(block_entry->flags & MPQFileValid)) ReturnValueWithError(nil, MPQErrorDomain, errFileIsInvalid, nil, error)
	
	// The info dictionary
	NSMutableDictionary* tempDict = [NSMutableDictionary dictionaryWithCapacity:0x10];
	
	// Hash table position (aka the file's position)
	[tempDict setObject:[NSNumber numberWithUnsignedInt:hash_position] forKey:MPQFileHashPosition];
	
	// Basic hash table information.
	[tempDict setObject:[NSNumber numberWithUnsignedInt:hash_entry->hash_a] forKey:MPQFileHashA];
	[tempDict setObject:[NSNumber numberWithUnsignedInt:hash_entry->hash_b] forKey:MPQFileHashB];
	[tempDict setObject:[NSNumber numberWithUnsignedShort:hash_entry->locale] forKey:MPQFileLocale];
	[tempDict setObject:[NSNumber numberWithUnsignedLong:hash_entry->platform] forKey:@"MPQFilePlatform"];
	
	// Encryption key
	uint32_t encryption_key = 0;
	if (block_entry->flags & MPQFileEncrypted) encryption_key = [self getFileEncryptionKey:hash_position];
	[tempDict setObject:[NSNumber numberWithUnsignedInt:encryption_key] forKey:MPQFileEncryptionKey];
	
	// Filename
	const char* filename = filename_table[hash_position];
	if (filename) {
		[tempDict setObject:[NSNumber numberWithBool:YES] forKey:MPQFileCanOpenWithoutFilename];
		[tempDict setObject:[NSString stringWithCString:filename encoding:NSASCIIStringEncoding] forKey:MPQFilename];
		[tempDict setObject:[NSNumber numberWithBool:NO] forKey:MPQSyntheticFilename];
	} else {
		// synthesize a unique name and determine if we can open the file without the filename anyways
		NSString* synthName = [NSString stringWithFormat:@"unknown %x", hash_position];
		uint32_t counter = 0;
		while ([self localesForFile:synthName] != nil) {
			synthName = [NSString stringWithFormat:@"unknown-%u %x", counter, hash_position];
			counter++;
		}
		
		[tempDict setObject:[NSString stringWithFormat:@"unknown %x", hash_position] forKey:MPQFilename];
		[tempDict setObject:[NSNumber numberWithBool:YES] forKey:MPQSyntheticFilename];
		[tempDict setObject:[NSNumber numberWithBool:((block_entry->flags & MPQFileEncrypted) && encryption_key == 0) ? NO : YES] forKey:MPQFileCanOpenWithoutFilename];
	}
	
	// If the file is pending addition, we need to get the size from the data source, not the block table entry
	uint32_t file_size = block_entry->size;
	
	mpq_deferred_operation_t* operation = operation_hash_table[hash_position];
	if (operation && operation->type == MPQDOAdd) {
		MPQDataSource* dataSource = [((mpq_deferred_operation_add_context_t*)operation->context)->dataSourceProxy createActualDataSource:error];
		if (!dataSource) return nil;
		
		off_t source_length = [dataSource length:error];
		[dataSource release];
		if (source_length == -1) return nil;
		
		// MPQ files can't be larger than uint32_t, so cast
		file_size = (uint32_t)source_length;
	}
	
	// block table info
	[tempDict setObject:[NSNumber numberWithUnsignedInt:file_size] forKey:MPQFileSize];
	[tempDict setObject:[NSNumber numberWithUnsignedInt:block_entry->archived_size] forKey:MPQFileArchiveSize];
	[tempDict setObject:[NSNumber numberWithUnsignedInt:block_entry->flags] forKey:MPQFileFlags];
	[tempDict setObject:[NSNumber numberWithLongLong:block_offset_table[hash_entry->block_table_index]] forKey:MPQFileArchiveOffset];
	
	// compute the number of sectors based on the file size (so explicitely ignore sector adlers)
	uint32_t sector_table_length;
	if ((block_entry->flags & MPQFileOneSector)) sector_table_length = 2;
	else sector_table_length = _MPQComputeSectorTableLength(full_sector_size, block_entry->size, (block_entry->flags & ~MPQFileHasSectorAdlers));
	[tempDict setObject:[NSNumber numberWithUnsignedInt:sector_table_length - 1] forKey:MPQFileNumberOfSectors];
	
	// Attributes
	if (attributes_data) {
		mpq_attributes_header_t* attributes = (mpq_attributes_header_t*)attributes_data;
		size_t currentOffset = sizeof(mpq_attributes_header_t);
		
		const mpq_file_attribute_t* attribute = mpq_file_attributes;
		while (attribute->flag != 0) {
			if ((attributes->attributes & attribute->flag)) {
				// We have that attribute
				NSData * dataWrapper = [NSData dataWithBytesNoCopy:(BUFFER_OFFSET(attributes_data, currentOffset + attribute->size * hash_entry->block_table_index)) 
															length:attribute->size 
													  freeWhenDone:NO];
				[tempDict setObject:[MPQFile performSelector:NSSelectorFromString(attribute->getter) withObject:dataWrapper] forKey:attribute->key];
				currentOffset += attribute->size * header.block_table_length;
			}
			attribute++;
		}
	}
	
	ReturnValueWithNoError(tempDict, error)
}

- (NSDictionary*)fileInfoForFile:(NSString*)filename locale:(MPQLocale)locale {
	return [self fileInfoForFile:filename locale:locale error:(NSError**)NULL];
}

- (NSDictionary*)fileInfoForFile:(NSString*)filename locale:(MPQLocale)locale error:(NSError**)error {
	NSParameterAssert(filename != nil);
	
	char* filename_cstring = _MPQCreateASCIIFilename(filename, error);
	if (!filename_cstring) return nil;
	
	// Find the file in the hash table
	uint32_t hash_position = [self findHashPosition:filename_cstring locale:locale error:error];
	if (hash_position == 0xffffffff) {
		free(filename_cstring);
		return nil;
	}
	
	// Make sure we have the filename in the name table
	if (!filename_table[hash_position]) filename_table[hash_position] = filename_cstring;
	else free(filename_cstring);
	filename_cstring = NULL;
	
	// Return the info dict
	return [self fileInfoForPosition:hash_position error:error];
}

- (NSArray*)fileInfoForFiles:(NSArray*)fileArray locale:(MPQLocale)locale {
	NSParameterAssert(fileArray != nil);
	NSMutableArray* tempArray = [NSMutableArray arrayWithCapacity:[fileArray count]];
	
	NSEnumerator* fileEnum = [fileArray objectEnumerator];
	NSString* aFile;
	NSDictionary* fileInfoDict;
	
	while ((aFile = [fileEnum nextObject])) {
		fileInfoDict = [self fileInfoForFile:aFile locale:locale];
		if (fileInfoDict) [tempArray addObject:fileInfoDict];
		else [tempArray addObject:[NSNull null]];
	}
	
	return tempArray;
}

#pragma mark delete

- (BOOL)deleteFileAtPosition:(uint32_t)hash_position error:(NSError**)error {
	NSParameterAssert(hash_position < header.hash_table_length);
	MPQDebugLog(@"deleting file at position %u", hash_position);
	
	// If the file is invalid, we can't delete it
	mpq_hash_table_entry_t* hash_entry = hash_table + hash_position;
	if (hash_entry->block_table_index == HASH_TABLE_DELETED) ReturnValueWithError(NO, MPQErrorDomain, errFileIsDeleted, nil, error)
	if (hash_entry->block_table_index == HASH_TABLE_EMPTY) ReturnValueWithError(NO, MPQErrorDomain, errHashTableEntryNotFound, nil, error)
	
	mpq_block_table_entry_t* block_entry = block_table + hash_entry->block_table_index;
	if (!(block_entry->flags & MPQFileValid)) ReturnValueWithError(NO, MPQErrorDomain, errFileIsInvalid, nil, error)
	
	// We have to make sure the file isn't opened
	if ([self openFileCountWithPosition:hash_position] > 0) ReturnValueWithError(NO, MPQErrorDomain, errFileIsOpen, nil, error)
	
	// Dirty the archive
	is_modified = YES;
	
	// Prepare a deferred operation
	mpq_deferred_operation_t* operation = malloc(sizeof(mpq_deferred_operation_t));
	operation->type = MPQDODelete;
	operation->context = NULL;
	
	operation->primary_file_context.hash_position = hash_position;
	operation->primary_file_context.hash_entry = *hash_entry;
	operation->primary_file_context.block_entry = *block_entry;
	operation->primary_file_context.block_offset = block_offset_table[hash_entry->block_table_index];
	operation->primary_file_context.encryption_key = encryption_keys_cache[hash_position];
	operation->primary_file_context.filename = 
		(filename_table[hash_position]) ? [[NSString alloc] initWithCString:filename_table[hash_position] encoding:NSASCIIStringEncoding] : nil;
	
	// Insert the deferred operation
	operation->previous = last_operation;
	last_operation = operation;
	operation_hash_table[hash_position] = operation;
	deferred_operations_count++;
	
	// Delete the hash table entry, and mark it as deleted. Note that deleted hash table entries are reused
	memset(hash_entry, 0xff, sizeof(mpq_hash_table_entry_t));
	hash_entry->block_table_index = HASH_TABLE_DELETED;
	
	// Mark the block entry as invalid
	block_entry->flags = 0;

	// Delete the name table entry (if there is one)
	if (filename_table[hash_position]) {
		free(filename_table[hash_position]);
		filename_table[hash_position] = NULL;
	}
	
	// Flush the encrytion key and sector table caches
	encryption_keys_cache[hash_position] = 0;
	if (sector_tables_cache[hash_position]) free(sector_tables_cache[hash_position]);
	sector_tables_cache[hash_position] = NULL;
	
	// mark the file count caches as dirty
	_fileCountCachesDirty = YES;
	
	ReturnValueWithNoError(YES, error)
}

- (BOOL)deleteFile:(NSString*)filename {
	return [self deleteFile:filename locale:MPQNeutral error:(NSError**)NULL];
}

- (BOOL)deleteFile:(NSString*)filename error:(NSError**)error {
	return [self deleteFile:filename locale:MPQNeutral error:error];
}

- (BOOL)deleteFile:(NSString*)filename locale:(MPQLocale)locale {
	return [self deleteFile:filename locale:locale error:(NSError**)NULL];
}

- (BOOL)deleteFile:(NSString*)filename locale:(MPQLocale)locale error:(NSError**)error {
	NSParameterAssert(filename != nil);
	
	if ([delegate respondsToSelector:@selector(archive:shouldDeleteFile:)])
		if (![delegate archive:self shouldDeleteFile:filename]) ReturnValueWithError(NO, MPQErrorDomain, errDelegateCancelled, nil, error)
	
	if ([delegate respondsToSelector:@selector(archive:willDeleteFile:)]) [delegate archive:self willDeleteFile:filename];
	
	// Convert the filename to ASCII
	char* filename_cstring = _MPQCreateASCIIFilename(filename, error);
	if (!filename_cstring) return NO;
	
	// See if the file exists by checking the hash table
	uint32_t hash_position = [self findHashPosition:filename_cstring locale:locale error:error];
	if (hash_position == 0xffffffff) {
		free(filename_cstring);
		return NO;
	}
	
	// Make sure we have the name in the name table
	if (!filename_table[hash_position]) filename_table[hash_position] = filename_cstring;
	else free(filename_cstring);
	filename_cstring = NULL;

	if (![self deleteFileAtPosition:hash_position error:error]) return NO;
	if ([delegate respondsToSelector:@selector(archive:didDeleteFile:)]) [delegate archive:self didDeleteFile:filename];
	ReturnValueWithNoError(YES, error)
}

#pragma mark adding

- (BOOL)addFileWithPath:(NSString*)path filename:(NSString*)filename parameters:(NSDictionary*)parameters {
	return [self addFileWithPath:path filename:filename parameters:parameters error:(NSError**)NULL];
}

- (BOOL)addFileWithPath:(NSString*)path filename:(NSString*)filename parameters:(NSDictionary*)parameters error:(NSError**)error {
	NSParameterAssert(path != nil);
	
	MPQDataSourceProxy* dataSourceProxy = [[MPQDataSourceProxy alloc] initWithPath:path error:error];
	if (!dataSourceProxy) return NO;
	
	BOOL result = [self addFileWithDataSourceProxy:dataSourceProxy filename:filename parameters:parameters error:error];
	[dataSourceProxy release];
	return result;
}

- (BOOL)addFileWithData:(NSData*)data filename:(NSString*)filename parameters:(NSDictionary*)parameters {
	return [self addFileWithData:data filename:filename parameters:parameters error:(NSError**)NULL];
}

- (BOOL)addFileWithData:(NSData*)data filename:(NSString*)filename parameters:(NSDictionary*)parameters error:(NSError**)error {
	NSParameterAssert(data != nil);
	
	MPQDataSourceProxy* dataSourceProxy = [[MPQDataSourceProxy alloc] initWithData:data error:error];
	if (!dataSourceProxy) return NO;
	
	BOOL result = [self addFileWithDataSourceProxy:dataSourceProxy filename:filename parameters:parameters error:error];
	[dataSourceProxy release];
	return result;
}

- (BOOL)addFileWithDataSourceProxy:(MPQDataSourceProxy*)dataSourceProxy filename:(NSString*)filename parameters:(NSDictionary*)parameters error:(NSError**)error {
	NSParameterAssert(dataSourceProxy != nil);
	NSParameterAssert(filename != nil);
	
	// Ask the delegate if we should add that file or not
	if ([delegate respondsToSelector:@selector(archive:shouldAddFile:)]) {
		if (![delegate archive:self shouldAddFile:filename])
			ReturnValueWithError(NO, MPQErrorDomain, errDelegateCancelled, nil, error)
	}
	
	// Debug log
	MPQDebugLog(@"adding %@", filename);

	// Convert filename to ASCII
	char* filename_cstring = _MPQCreateASCIIFilename(filename, error);
	if (!filename_cstring)
		return NO;
	
	// Prepare add parameters
	uint32_t flags = MPQFileCompressed;
	uint16_t locale = MPQNeutral;
	uint32_t compressor = default_compressor;
	int32_t compression_quality = 0;
	BOOL overwrite = NO;
	
	// Set the compression quality depending on the compressor
	if (compressor == MPQZLIBCompression)
		compression_quality = Z_DEFAULT_COMPRESSION;
	else if (compressor == MPQBZIP2Compression)
		compression_quality = 9;
	else if ((compressor & (MPQStereoADPCMCompression | MPQMonoADPCMCompression)))
		compression_quality = MPQADPCMQualityHigh;
	
	// If we have parameters, validate them now
	if (parameters) {
		NSNumber* tempNum = nil;
		if ((tempNum = [parameters objectForKey:MPQFileFlags]))
			flags = [tempNum unsignedIntValue];
		if ((tempNum = [parameters objectForKey:MPQFileLocale]))
			locale = [tempNum unsignedShortValue];
		if ((tempNum = [parameters objectForKey:MPQOverwrite]))
			overwrite = [tempNum boolValue];
		
		// Check the compression flags
		if ((flags & MPQFileDiabloCompressed) && (flags & MPQFileCompressed)) {
			MPQDebugLog(@"inconsistent compression flags");
			free(filename_cstring);
			ReturnValueWithError(NO, MPQErrorDomain, errInconsistentCompressionFlags, nil, error)
		}
		
		// TODO: need to validate the locale
		
		// TODO: Currently we don't support MPQFileHasSectorAdlers
		flags &= ~MPQFileHasSectorAdlers;
		
		// TODO" Currently we don't support MPQFileStopSearchMarker
		flags &= ~MPQFileStopSearchMarker;
		
		// Compressor
		if ((tempNum = [parameters objectForKey:MPQCompressor])) {
			compressor = [tempNum unsignedIntValue];
			
			// Make sure the compressor is valid
			if ((compressor & ~MPQCompressorMask))	{
				MPQDebugLog(@"invalid compressor");
				free(filename_cstring);
				ReturnValueWithError(NO, MPQErrorDomain, errInvalidCompressor, nil, error)
			}
		}
		
		// Silently force the PKWARE compressor if the MPQFileDiabloCompressed flag is set
		if ((flags & MPQFileDiabloCompressed))
			compressor = MPQPKWARECompression;
		
		// Set the compression quality depending on the compressor
		if (compressor == MPQZLIBCompression)
			compression_quality = Z_DEFAULT_COMPRESSION;
		else if (compressor == MPQBZIP2Compression)
			compression_quality = 9;
		else if ((compressor & (MPQMonoADPCMCompression | MPQStereoADPCMCompression)))
			compression_quality = MPQADPCMQualityHigh;
		
		// Compression quality
		if ((tempNum = [parameters objectForKey:MPQCompressionQuality])) {
			compression_quality = [tempNum intValue];
			
			// Silently make sure the compression quality is valid for the compressor
			if (compressor == MPQZLIBCompression && (compression_quality < -1 || compression_quality > 9))
				compression_quality = Z_DEFAULT_COMPRESSION;
			else if ((compressor & (MPQMonoADPCMCompression | MPQStereoADPCMCompression)) && (compression_quality < MPQADPCMQualityLow || compression_quality > MPQADPCMQualityHigh))
				compression_quality = MPQADPCMQualityHigh;
			else if (compressor == MPQBZIP2Compression && (compression_quality < 1 || compression_quality > 9))
				compression_quality = 9;
		}
	}
	
	// The requested filename might already be in use
	uint32_t old_hash_position = [self findHashPosition:filename_cstring locale:locale error:error];
	if (old_hash_position != 0xffffffff) {
		if (overwrite) {
			// Make sure the name of the file we are about to delete is in the name table, otherwise, we won't be able to un-delete it!
			// This would normally be done by the delete methods, but to save us a hashing we're going to call deleteFileAtPosition directly.
			if (!filename_table[old_hash_position])
				filename_table[old_hash_position] = _MPQCreateASCIIFilename(filename, (NSError**)NULL);
			
			// Delete the existing file
			MPQDebugLog(@"deleting existing file");
			if (![self deleteFileAtPosition:old_hash_position error:error]) {
				MPQDebugLog(@"can't delete existing file");
				free(filename_cstring);
				return NO;
			}
		} else {
			MPQDebugLog(@"adding failed, file with requested filename exists and not allowed to delete it");
			free(filename_cstring);
			ReturnValueWithError(NO, MPQErrorDomain, errFileExists, nil, error)
		}
	}
	
	// In order to add the file, there must be a free slot in both the hash and block tables
	uint32_t hash_position = [self createHashPosition:filename_cstring error:error];
	if (hash_position == 0xffffffff) {
		MPQDebugLog(@"no space in hash table");
		free(filename_cstring);
		return NO;
	}
	
	uint32_t block_position = [self createBlockTablePosition:0 error:error];
	if (block_position == 0xffffffff) {
		MPQDebugLog(@"no space in block table");
		free(filename_cstring);
		return NO;
	}
	
	// The file's encryption key is the hash of the filename only
	const char* filename_name_cstring = strrchr(filename_cstring, '\\');
	if (filename_name_cstring)
		filename_name_cstring++;
	else
		filename_name_cstring = filename_cstring;
		
	// Compute the encryption key
	uint32_t encryption_key = mpq_hash_cstring(filename_name_cstring, HASH_KEY);
	
	// We can't offset adjust the key here
	
	// Prepare a deferred operation
	mpq_deferred_operation_t* operation = malloc(sizeof(mpq_deferred_operation_t));
	operation->type = MPQDOAdd;
	
	mpq_deferred_operation_add_context_t* context = malloc(sizeof(mpq_deferred_operation_add_context_t));
	operation->context = context;
	
	operation->primary_file_context.hash_position = hash_position;
	operation->primary_file_context.hash_entry = hash_table[hash_position];
	operation->primary_file_context.block_entry = block_table[block_position];
	operation->primary_file_context.block_offset = block_offset_table[block_position];
	operation->primary_file_context.encryption_key = encryption_key;
	operation->primary_file_context.filename = [filename copy];
	
	context->dataSourceProxy = [dataSourceProxy retain];
	context->compressor = compressor;
	context->compression_quality = compression_quality;
		
	// Insert the deferred operation
	operation->previous = last_operation;
	last_operation = operation;
	operation_hash_table[hash_position] = operation;
	deferred_operations_count++;

	// The MPQ is now modified
	is_modified = YES;

	// Add the file to the block table
	block_table[block_position].size = 0;
	block_table[block_position].archived_size = 0;
	block_table[block_position].flags = (flags & MPQFileFlagsMask) | MPQFileValid;

	// Add the file to the hash table
	hash_table[hash_position].hash_a = mpq_hash_cstring(filename_cstring, HASH_NAME_A);
	hash_table[hash_position].hash_b = mpq_hash_cstring(filename_cstring, HASH_NAME_B);
	hash_table[hash_position].locale = locale;
	hash_table[hash_position].platform = 0;
	hash_table[hash_position].block_table_index = block_position;

	// Give up ownership of the ASCII filename buffer to the filename table
	filename_table[hash_position] = filename_cstring;
		
	// Cache the crypt key
	encryption_keys_cache[hash_position] = encryption_key;
	
	// mark the file count caches as dirty
	_fileCountCachesDirty = YES;
	
	ReturnValueWithNoError(YES, error)
}

- (BOOL)_performFileAddOperation:(mpq_deferred_operation_t*)operation error:(NSError**)error {
	NSParameterAssert(operation != NULL);
	NSParameterAssert(operation->type == MPQDOAdd);
	mpq_deferred_operation_add_context_t* context = (mpq_deferred_operation_add_context_t*)operation->context;
	
	MPQDebugLog(@"adding %@", operation->primary_file_context.filename);
	
	// Get a data source from the data source proxy
	MPQDataSource* dataSource = [context->dataSourceProxy createActualDataSource:error];
	if (dataSource == nil)
		return NO;
	
	uint32_t hash_position = operation->primary_file_context.hash_position;
	uint32_t block_position = hash_table[hash_position].block_table_index;
	
	// Get the size of the file to add
	off_t data_size = [dataSource length:error];
	if (data_size == -1) {
		[dataSource release];
		return NO;
	}
	MPQDebugLog2(@"    size of input file: %llu", data_size);
	
	// Check for data length overflow
	if (data_size > UINT32_MAX) {
		[dataSource release];
		ReturnValueWithError(NO, MPQErrorDomain, errDataTooLarge, nil, error)
	}
	
	// We now know this cast is safe
	uint32_t file_size = (uint32_t)data_size;
	block_table[block_position].size = file_size;
	
	// If we have less data than the compression threshold, compression won't be very useful, and will just slow things down
	if (file_size < COMPRESSION_THRESHOLD) {
		MPQDebugLog2(@"    less data than compression threshold");
		block_table[block_position].flags &= ~(MPQFileCompressed | MPQFileDiabloCompressed);
	}
	
	// If we have less than 4 bytes, no encryption and no offset adjusted key
	if (data_size < 4)
		block_table[block_position].flags &= ~(MPQFileOffsetAdjustedKey | MPQFileEncrypted);
	
	// Copy the file flags for easier access in this method
	uint32_t flags = block_table[block_position].flags;
	
	if ((flags & MPQFileCompressed))
		MPQDebugLog2(@"    compressor: %u, compression quality: %d", context->compressor, context->compression_quality);
	
	// Predicate for needing a sector table
	BOOL needs_sector_table = ((flags & (MPQFileDiabloCompressed | MPQFileCompressed)) && !(flags & MPQFileOneSector)) ? YES : NO;
	
	// Compute the length and size of the sector table
	uint32_t sector_table_length = (needs_sector_table) ? _MPQComputeSectorTableLength(full_sector_size, file_size, flags) : 0;
	// Explicit cast is OK here, sector table sizes are 32-bit
	uint32_t sector_table_size = sector_table_length * (uint32_t)sizeof(uint32_t);
	MPQDebugLog2(@"    entries in sector table: %u", sector_table_length);
	
	// Allocate memory for the file's compressed sector table (if we need one)
	uint32_t* sector_table = NULL;
	if (needs_sector_table)
		sector_table = malloc(sector_table_size);
	if (!sector_table && needs_sector_table) {
		[dataSource release];
		ReturnValueWithError(NO, MPQErrorDomain, errOutOfMemory, nil, error)
	}
	
	// Compression state
	uint32_t current_sector_size = 0;
	uint32_t remaining_data_size = file_size;
	uint32_t compressed_size = 0;
	uint32_t current_sector = 0;
	uint32_t file_compressed_size = 0;
	off_t data_offset = 0;
	ssize_t read_sector_size = 0;
	
	// Precalculate the offset of the file
	off_t file_write_offset = block_offset_table[block_position];
	
	// If the file write offset is zero, we may need to resize the archive file
	if (file_write_offset == 0) {
		// Set the file write offset to the archive write offset
		file_write_offset = archive_write_offset;
		
		struct stat sb;
		if (fstat(archive_fd, &sb) == -1) {
			if (sector_table)
				free(sector_table);
			[dataSource release];
			ReturnValueWithError(NO, NSPOSIXErrorDomain, errno, nil, error)
		}
		
		// Compute a few archive space quantities
		off_t available_space = sb.st_size - file_write_offset;
		off_t required_space = file_size + sector_table_size;
		off_t missing_space = required_space - available_space;
		
		// If we'll be writing the file data beyond the 4 GB limit, we'll need an EBOT
		BOOL mustResetEBOTOnFailure = NO;
		if (file_write_offset > UINT32_MAX && header.version == 1 && extended_header.extended_block_offset_table_offset == 0) {
			// 1 is enough to have computeSizeOfStructuralTables take an EBOT into account
			extended_header.extended_block_offset_table_offset = 1;
			mustResetEBOTOnFailure = YES;
		}
		
		// We can now take into account the space required by structural tables
		missing_space += [self _computeSizeOfStructuralTables];
		
		// We only need to resize if there is not enough space for the new file
		if (missing_space > 0) {
			if (![self _truncateArchiveWithDelta:missing_space error:error]) {
				if (sector_table)
					free(sector_table);
				[dataSource release];
				if (mustResetEBOTOnFailure)
					extended_header.extended_block_offset_table_offset = 0;
				return NO;
			}
		}
	}
	
	// Get the precalculated encryption key
	uint32_t encryption_key = encryption_keys_cache[hash_position];
		
	// We can now offset adjust the key properly
	if ((flags & MPQFileOffsetAdjustedKey)) {
		encryption_key = (encryption_key + (uint32_t)file_write_offset) ^ file_size;
		encryption_keys_cache[hash_position] = encryption_key;
	}
	
	// Adjust the file's compressed size for the sector table
	file_compressed_size += sector_table_size;
	
	// First sector table entry is the size of the sector table itself
	if (needs_sector_table)
		sector_table[0] = file_compressed_size;
	
	// Prime the compression buffer
	memset(compression_buffer, 0, full_sector_size + 1);
	
	// Add the entire file to the end of the MPQ, processing it sector by sector
	MPQDebugLog2(@"    writing sectors...");
	while (remaining_data_size > 0) {
		// Compute the size of the sector
		current_sector_size = (flags & MPQFileOneSector) ? remaining_data_size : MIN(remaining_data_size, full_sector_size);
		compressed_size = full_sector_size << 1;

		// Read the current sector
		read_sector_size = [dataSource pread:read_buffer size:current_sector_size offset:data_offset error:error];
		if ((uint32_t)read_sector_size != current_sector_size) {
			if (sector_table)
				free(sector_table);
			[dataSource release];
			return NO;
		}

		// This is to correct the idiosynchrosies of the Diablo compression
		char* buffer_pointer = compression_buffer;
			
		// Compress the sector with whatever compression method is specified
		// TODO: stream compression when one sector is set
		if ((flags & (MPQFileCompressed | MPQFileDiabloCompressed))) {
			int compression_error = 0;
			if ((context->compressor & (MPQMonoADPCMCompression | MPQStereoADPCMCompression))) {
				// Make sure to use PKWARE on the first sector to not garble up AIFF / WAV / etc headers. Of course this is a naive workaround...
				compression_error = SCompCompress(compression_buffer, 
												  &compressed_size, 
												  read_buffer, 
												  current_sector_size, 
												  (current_sector == 0) ? MPQPKWARECompression : context->compressor, 
												  0, 
												  context->compression_quality);
			} else if ((flags & MPQFileDiabloCompressed)) {
				// Diablo compression means to assume PKWARE compression, and therefore no compression type byte is prepended to the bitstream
				compression_error = SCompCompress(compression_buffer, &compressed_size, read_buffer, current_sector_size, context->compressor, 0, 0);
				if (compression_error && compressed_size < current_sector_size) {
					buffer_pointer++;
					compressed_size--;
				}
			} else if ((flags & MPQFileCompressed)) {
				compression_error = SCompCompress(compression_buffer, 
												  &compressed_size, 
												  read_buffer, 
												  current_sector_size, 
												  context->compressor, 
												  0, 
												  context->compression_quality);
			}
			
			// If the compression failed or we didn't save any bytes, we reject the compressed block
			if (!compression_error || (compressed_size >= (current_sector_size - 1))) {
				MPQDebugLog2(@"    scrapping compressed sector");
				compressed_size = current_sector_size;
				memcpy(compression_buffer, read_buffer, compressed_size);
			}
		} else {
			// No compression, just do straight copy
			compressed_size = current_sector_size;
			memcpy(compression_buffer, read_buffer, compressed_size);
		}

		// Encrypt the sector if necessary
		if ((flags & MPQFileEncrypted))
			mpq_encrypt(buffer_pointer, compressed_size, encryption_key + current_sector, NO);

		// Write the sector
		if (pwrite(archive_fd, buffer_pointer, compressed_size, archive_offset + file_write_offset + file_compressed_size) == -1) {
			if (sector_table)
				free(sector_table);
			[dataSource release];
			ReturnValueWithError(NO, NSPOSIXErrorDomain, errno, nil, error)
		}
		
		// Update the compression state
		data_offset += current_sector_size;
		remaining_data_size -= current_sector_size;
		file_compressed_size += compressed_size;
		current_sector++;

		// Add the sector's size to the sector table
		if (needs_sector_table)
			sector_table[current_sector] = file_compressed_size;
	}
	
	// May have a sector table to write
	if (needs_sector_table) {
		MPQDebugLog2(@"    writing sector table...");
		MPQDebugLog2(@"    size of sector table: %u", sector_table_size);
		
		// If the file is encrypted, we need to encrypt the sector table as well. Since the sector table is just an array
		// of uint32_t, we can disable input swapping on the encrypt function and get the encrypted sector table in
		// little endian. If we are not encrypting, we must explicitely swap the sector table.
		if ((flags & MPQFileEncrypted))
			mpq_encrypt((char*)sector_table, sector_table_size, encryption_key - 1, YES);
		else
			[[self class] swap_uint32_array:sector_table length:sector_table_length];

		// Write the sector table
		if (pwrite(archive_fd, sector_table, sector_table_size, archive_offset + file_write_offset) == -1) {
			if (sector_table)
				free(sector_table);
			[dataSource release];
			ReturnValueWithError(NO, NSPOSIXErrorDomain, errno, nil, error)
		}
	}

	// Update the file's entry in the block table
	block_offset_table[block_position] = file_write_offset;
	block_table[block_position].archived_size = file_compressed_size;
	MPQDebugLog2(@"    compressed size: %u", file_compressed_size);
		
	// Update the archive write offset if we wrote at the end of the archive
	if (archive_write_offset == file_write_offset)
		archive_write_offset += file_compressed_size;
	
	MPQDebugLog2(@"    done adding %@", operation->primary_file_context.filename);
	
	if (sector_table)
		free(sector_table);
	[dataSource release];
	return YES;
}

#pragma mark opening

- (MPQFile*)openFileAtPosition:(uint32_t)hash_position error:(NSError**)error {
	NSParameterAssert(hash_position < header.hash_table_length);
	
	// If the file is invalid, we can't open it
	mpq_hash_table_entry_t* hash_entry = &hash_table[hash_position];
	if (hash_entry->block_table_index == HASH_TABLE_DELETED) ReturnValueWithError(nil, MPQErrorDomain, errFileIsDeleted, nil, error)
	if (hash_entry->block_table_index == HASH_TABLE_EMPTY) ReturnValueWithError(nil, MPQErrorDomain, errHashTableEntryNotFound, nil, error)
	
	mpq_block_table_entry_t* block_entry = block_table + hash_entry->block_table_index;
	if (!(block_entry->flags & MPQFileValid)) ReturnValueWithError(nil, MPQErrorDomain, errFileIsInvalid, nil, error)
	
	char* filename_cstring = filename_table[hash_position];
	NSString* filename = nil;
	if (filename_cstring) {
		filename = [[[NSString alloc] initWithBytesNoCopy:filename_cstring 
												   length:strlen(filename_cstring) 
												 encoding:NSASCIIStringEncoding 
											 freeWhenDone:NO] autorelease];
	} else {
		// Generate a temporary filename for MPQFile
		filename = [NSString stringWithFormat:@"unknown %x", hash_position];
	}
	
	// Ask the delgate if we should proceed
	if ([delegate respondsToSelector:@selector(archive:shouldOpenFile:)])
		if (![delegate archive:self shouldOpenFile:filename]) ReturnValueWithError(nil, MPQErrorDomain, errDelegateCancelled, nil, error)
	
	// Notify the delgate we're going ahead
	if ([delegate respondsToSelector:@selector(archive:willOpenFile:)]) [delegate archive:self willOpenFile:filename];
	
	// We need to check the operation table to see if we hit a file that's pending for addition
	mpq_deferred_operation_t* operation = operation_hash_table[hash_position];
	if (operation) {
		if (operation->type == MPQDOAdd) {
			// Client requested a file pending for addition
			NSDictionary* config = [[NSDictionary alloc] initWithObjectsAndKeys:
				self, @"Parent", 
				[NSNumber numberWithUnsignedInt:hash_position], @"Position",
				[NSValue valueWithPointer:hash_entry], @"HashTableEntry",
				[NSValue valueWithPointer:block_entry], @"BlockTableEntry",
				((mpq_deferred_operation_add_context_t*)operation->context)->dataSourceProxy, @"DataSourceProxy",
				filename, @"Filename",
				nil];
			
			Class fileClass = NSClassFromString(@"MPQFileDataSource");
			MPQFile* file = [[fileClass alloc] initForFile:config error:error];
			
			// Notify the delegate we're done
			if ([delegate respondsToSelector:@selector(archive:didOpenFile:)]) [delegate archive:self didOpenFile:file];
			
			[config release];
			ReturnValueWithNoError(file, error)
		}
	}
	
	// If the file is encrypted, we need the encryption key
	uint32_t encryption_key = 0;
	if (block_entry->flags & MPQFileEncrypted) {
		encryption_key = [self getFileEncryptionKey:hash_position];
		// TODO: what if 0 can be a legitimate encryption key?
		if (encryption_key == 0) ReturnValueWithError(nil, MPQErrorDomain, errFilenameRequired, nil, error)
	}
	
	// We behave differently if the file is a one sector file
	if ((block_entry->flags & MPQFileOneSector)) {
		NSDictionary* config = [[NSDictionary alloc] initWithObjectsAndKeys:
			self, @"Parent",
			filename, @"Filename",
			[NSNumber numberWithUnsignedInt:encryption_key], @"EncryptionKey",
			[NSNumber numberWithInt:archive_fd], @"FileDescriptor",
			[NSNumber numberWithLongLong:archive_offset + block_offset_table[hash_entry->block_table_index]], @"FileArchiveOffset",
			[NSNumber numberWithUnsignedInt:hash_position], @"Position",
			[NSValue valueWithPointer:hash_entry], @"HashTableEntry",
			[NSValue valueWithPointer:block_entry], @"BlockTableEntry",
			nil];
		
		Class fileClass = NSClassFromString(@"MPQFileConcreteMPQOneSector");
		MPQFile* file = [[fileClass alloc] initForFile:config error:error];
		
		// Notify the delegate we're done
		if ([delegate respondsToSelector:@selector(archive:didOpenFile:)]) [delegate archive:self didOpenFile:file];
		
		[config release];
		ReturnValueWithNoError(file, error)
	}
	
	// Load the sector table in cache (or do nothing if we already have it)
	[self _cacheSectorTableForFile:hash_position key:encryption_key error:error];
	
	// Check that we have a sector table if we need one
	uint32_t* sector_table = sector_tables_cache[hash_position];
	if ((block_entry->flags & (MPQFileCompressed | MPQFileDiabloCompressed)) && !sector_table) {
		ReturnValueWithError(nil, MPQErrorDomain, errInvalidSectorTableCache, nil, error)
	}
	
	// Get the sector table length (and explicitely ignore sector adlers)
	uint32_t sector_table_length = _MPQComputeSectorTableLength(full_sector_size, block_entry->size, (block_entry->flags & ~MPQFileHasSectorAdlers));
	
	NSDictionary* config = [[NSDictionary alloc] initWithObjectsAndKeys:
		self, @"Parent",
		filename, @"Filename",
		[NSNumber numberWithUnsignedInt:encryption_key], @"EncryptionKey",
		[NSNumber numberWithInt:archive_fd], @"FileDescriptor",
		[NSNumber numberWithLongLong:archive_offset + block_offset_table[hash_entry->block_table_index]], @"FileArchiveOffset",
		[NSNumber numberWithUnsignedInt:hash_position], @"Position",
		[NSValue valueWithPointer:hash_entry], @"HashTableEntry",
		[NSValue valueWithPointer:block_entry], @"BlockTableEntry",
		[NSNumber numberWithUnsignedInt:header.sector_size_shift], @"SectorSizeShift",
		[NSNumber numberWithUnsignedInt:sector_table_length], @"SectorTableLength",
		[NSValue valueWithPointer:sector_table], @"SectorTable",
		nil];
	
	Class fileClass = NSClassFromString(@"MPQFileConcreteMPQ");
	MPQFile* file = [[fileClass alloc] initForFile:config error:error];
	
	// Notify the delegate we're done
	if ([delegate respondsToSelector:@selector(archive:didOpenFile:)]) [delegate archive:self didOpenFile:file];
	
	[config release];
	ReturnValueWithNoError(file, error)
}

- (MPQFile*)openFile:(NSString*)filename {
	return [self openFile:filename locale:MPQNeutral error:(NSError**)NULL];
}

- (MPQFile*)openFile:(NSString*)filename error:(NSError**)error {
	return [self openFile:filename locale:MPQNeutral error:error];
}

- (MPQFile*)openFile:(NSString*)filename locale:(MPQLocale)locale {
	return [self openFile:filename locale:locale error:(NSError**)NULL];
}

- (MPQFile*)openFile:(NSString*)filename locale:(MPQLocale)locale error:(NSError**)error {
	NSParameterAssert(filename != nil);
	
	char* filename_cstring = _MPQCreateASCIIFilename(filename, error);
	if (!filename_cstring) return nil;

	// See if the requested file exists in the specified language
	uint32_t hash_position = [self findHashPosition:filename_cstring locale:locale error:error];
	if (hash_position == 0xffffffff) {
		free(filename_cstring);
		return nil;
	}
	
	// Make sure we have the name in the name table
	if (!filename_table[hash_position]) filename_table[hash_position] = filename_cstring;
	else free(filename_cstring);
	filename_cstring = NULL;
	
	// openFileAtPosition does the rest
	return [self openFileAtPosition:hash_position error:error];
}

#pragma mark reading

- (NSData*)copyDataForFile:(NSString*)filename {
	return [self copyDataForFile:filename range:NSMakeRange(0, 0) locale:MPQNeutral error:(NSError**)NULL];
}

- (NSData*)copyDataForFile:(NSString*)filename error:(NSError**)error {
	return [self copyDataForFile:filename range:NSMakeRange(0, 0) locale:MPQNeutral error:error];
}

- (NSData*)copyDataForFile:(NSString*)filename range:(NSRange)dataRange {
	return [self copyDataForFile:filename range:dataRange locale:MPQNeutral error:(NSError**)NULL];
}

- (NSData*)copyDataForFile:(NSString*)filename range:(NSRange)dataRange error:(NSError**)error {
	return [self copyDataForFile:filename range:dataRange locale:MPQNeutral error:error];
}

- (NSData*)copyDataForFile:(NSString*)filename locale:(MPQLocale)locale {
	return [self copyDataForFile:filename range:NSMakeRange(0, 0) locale:locale error:(NSError**)NULL];
}

- (NSData*)copyDataForFile:(NSString*)filename locale:(MPQLocale)locale error:(NSError**)error {
	return [self copyDataForFile:filename range:NSMakeRange(0, 0) locale:locale error:error];
}

- (NSData*)copyDataForFile:(NSString*)filename range:(NSRange)dataRange locale:(MPQLocale)locale {
	return [self copyDataForFile:filename range:dataRange locale:locale error:(NSError**)NULL];
}

- (NSData*)copyDataForFile:(NSString*)filename range:(NSRange)dataRange locale:(MPQLocale)locale error:(NSError**)error {
	MPQFile* theFile = [self openFile:filename locale:locale error:error];
	if (!theFile) return nil;
	
	NSData* returnData = nil;
	if (dataRange.length == 0) {
		[theFile seekToFileOffset:dataRange.location];
		returnData = [theFile copyDataToEndOfFile];
	} else {
		[theFile seekToFileOffset:dataRange.location];
		// Explicit cast is OK here, MPQ file sizes are 32-bit
		returnData = [theFile copyDataOfLength:(uint32_t)dataRange.length];
	}
	
	[theFile release];
	ReturnValueWithNoError(returnData, error)
}

#pragma mark existence

- (BOOL)fileExists:(NSString*)filename {
	return [self fileExists:filename locale:MPQNeutral error:(NSError**)NULL];
}

- (BOOL)fileExists:(NSString*)filename error:(NSError**)error {
	return [self fileExists:filename locale:MPQNeutral error:error];
}

- (BOOL)fileExists:(NSString*)filename locale:(MPQLocale)locale {
	return [self fileExists:filename locale:locale error:(NSError**)NULL];
}

- (BOOL)fileExists:(NSString*)filename locale:(MPQLocale)locale error:(NSError**)error {
	NSParameterAssert(filename != nil);

	char* filename_cstring = _MPQCreateASCIIFilename(filename, error);
	if (!filename_cstring) return NO;
	
	// Find the file in the hash table
	uint32_t hash_position = [self findHashPosition:filename_cstring locale:locale error:error];
	if (hash_position != 0xffffffff) {
		if (!filename_table[hash_position]) filename_table[hash_position] = filename_cstring;
		else free(filename_cstring);
		return YES;
	} else {
		free(filename_cstring);
		return NO;
	}
}

- (NSArray*)localesForFile:(NSString*)filename {
	NSParameterAssert(filename != nil);
	
	char* filename_cstring = _MPQCreateASCIIFilename(filename, (NSError**)NULL);
	if (!filename_cstring) return nil;
	
	// Compute the starting hash table offset, as well as the verification hashes for the specified file.
	uint32_t initial_hash_position = mpq_hash_cstring(filename_cstring, HASH_POSITION) % header.hash_table_length,
		current_hash_position = initial_hash_position,
		hash_a = mpq_hash_cstring(filename_cstring, HASH_NAME_A),
		hash_b = mpq_hash_cstring(filename_cstring, HASH_NAME_B);
	free(filename_cstring);
	filename_cstring = NULL;

	// If the first entry we find is empty, we're done
	if (hash_table[current_hash_position].block_table_index == HASH_TABLE_EMPTY) return nil;
	
	NSMutableArray* locales = [[NSMutableArray alloc] initWithCapacity:0x10];
	do {
		if (hash_table[current_hash_position].hash_a == hash_a &&
			hash_table[current_hash_position].hash_b == hash_b &&
			hash_table[current_hash_position].block_table_index != HASH_TABLE_DELETED)
		{
			// Make sure we have the name in the name table
			if (!filename_table[current_hash_position]) filename_table[current_hash_position] = _MPQCreateASCIIFilename(filename, (NSError**)NULL);
			[locales addObject:[NSNumber numberWithUnsignedInt:hash_table[current_hash_position].locale]];
		}
		
		current_hash_position++;
		current_hash_position %= header.hash_table_length;
	} while ((current_hash_position != initial_hash_position) && (hash_table[current_hash_position].block_table_index != HASH_TABLE_EMPTY));
	
	if ([locales count] == 0) {
		[locales release];
		locales = nil;
	} else [locales autorelease];
	return locales;
}

#pragma mark writing

- (BOOL)writeToFile:(NSString*)path atomically:(BOOL)atomically {
	return [self writeToFile:path atomically:atomically error:(NSError**)NULL];
}

- (BOOL)_writeStructuralTables:(NSError**)error {
	// Quantities to process the structural tables
	ssize_t bytes_written = 0;
	
	// Update the offset and size of the structural tables
	size_t hash_table_size = header.hash_table_length * sizeof(mpq_hash_table_entry_t);
	size_t block_table_size = header.block_table_length * sizeof(mpq_block_table_entry_t);
	
	hash_table_offset = archive_write_offset;
	block_table_offset = archive_write_offset + hash_table_size;
	
	// Update the archive headers
	// Explicit cast is OK here, header_size is 32-bit
	header.header_size = (header.version == 0) ? (uint32_t)sizeof(mpq_header_t) : (uint32_t)(sizeof(mpq_header_t) + sizeof(mpq_extended_header_t));
	header.archive_size = (header.version == 0) ? (uint32_t)archive_size : 0;
	header.hash_table_offset = (uint32_t)(hash_table_offset & 0xFFFFFFFF);
	header.block_table_offset = (uint32_t)(block_table_offset & 0xFFFFFFFF);
	
	if (header.version == 1) {
		extended_header.hash_table_offset_high = (uint16_t)(hash_table_offset >> 32);
		extended_header.block_table_offset_high = (uint16_t)(block_table_offset >> 32);
		if (extended_header.extended_block_offset_table_offset == 1) extended_header.extended_block_offset_table_offset = block_table_offset + block_table_size;
	}
	
	// Compute block table offset fields and the extended block offset table (if needed)
	mpq_extended_block_offset_table_entry_t* extended_block_offset_table = NULL;
	uint32_t i = 0;
	if (extended_header.extended_block_offset_table_offset != 0) {
		extended_block_offset_table = malloc(header.block_table_length * sizeof(mpq_extended_block_offset_table_entry_t));
		if (extended_block_offset_table == NULL) ReturnValueWithError(NO, MPQErrorDomain, errOutOfMemory, nil, error)
		
		for (; i < header.block_table_length; i++) {
			block_table[i].offset = (uint32_t)(block_offset_table[i] & 0xFFFFFFFF);
			extended_block_offset_table[i].offset_high = (uint16_t)(block_offset_table[i] >> 32);
		}
	} else {
		for (; i < header.block_table_length; i++) block_table[i].offset = (uint32_t)(block_offset_table[i]);
	}

	// Write the header
	[[self class] swap_mpq_header:&header];
	bytes_written = pwrite(archive_fd, &header, sizeof(mpq_header_t), archive_offset);
	if (bytes_written < (ssize_t)sizeof(mpq_header_t)) {
		if (extended_block_offset_table) free(extended_block_offset_table);
		ReturnValueWithError(NO, NSPOSIXErrorDomain, errno, nil, error)
	}
	[[self class] swap_mpq_header:&header];
	
	// Write the extended header
	if (header.version == 1) {
		[[self class] swap_mpq_extended_header:&extended_header];
		bytes_written = pwrite(archive_fd, &extended_header, sizeof(mpq_extended_header_t), archive_offset + sizeof(mpq_header_t));
		if (bytes_written < (ssize_t)sizeof(mpq_extended_header_t)) {
			if (extended_block_offset_table) free(extended_block_offset_table);
			ReturnValueWithError(NO, NSPOSIXErrorDomain, errno, nil, error)
		}
		[[self class] swap_mpq_extended_header:&extended_header];
	}

	// Encrypt the hash table
	[self swap_hash_table];
	mpq_encrypt((char*)hash_table, hash_table_size, mpq_hash_cstring(kHashTableEncryptionKey, HASH_KEY), NO);

	// And write it to the archive
	bytes_written = pwrite(archive_fd, hash_table, hash_table_size, archive_offset + archive_write_offset);
	if (bytes_written < (ssize_t)hash_table_size) {
		if (extended_block_offset_table) free(extended_block_offset_table);
		ReturnValueWithError(NO, NSPOSIXErrorDomain, errno, nil, error)
	}
	
	// Encrypt and write the block table. Since that's an array of uint32_t, skip input swapping.
	mpq_encrypt((char*)block_table, block_table_size, mpq_hash_cstring(kBlockTableEncryptionKey, HASH_KEY), YES);

	// Write the block table
	bytes_written = pwrite(archive_fd, block_table, block_table_size, archive_offset + archive_write_offset + hash_table_size);
	if (bytes_written < (ssize_t)block_table_size) {
		if (extended_block_offset_table) free(extended_block_offset_table);
		ReturnValueWithError(NO, NSPOSIXErrorDomain, errno, nil, error)
	}

	// Decrypt and re-flip the hash table
	mpq_decrypt((char*)hash_table, hash_table_size, mpq_hash_cstring(kHashTableEncryptionKey, HASH_KEY), NO);
	[self swap_hash_table];
	
	// Decrypt the block table. Since it's only an array of unsigned longs, disable output swapping.
	mpq_decrypt((char*)block_table, block_table_size, mpq_hash_cstring(kBlockTableEncryptionKey, HASH_KEY), YES);
	
	// Write the extended block offset table
	if (extended_header.extended_block_offset_table_offset != 0) {
		size_t extended_block_offset_table_size = header.block_table_length * sizeof(mpq_extended_block_offset_table_entry_t);
		[self swap_extended_block_offset_table:extended_block_offset_table length:header.block_table_length];
		bytes_written = pwrite(archive_fd, 
							   extended_block_offset_table, 
							   extended_block_offset_table_size, 
							   archive_offset + extended_header.extended_block_offset_table_offset);
		free(extended_block_offset_table);
		if (bytes_written < (ssize_t)extended_block_offset_table_size) ReturnValueWithError(NO, NSPOSIXErrorDomain, errno, nil, error)
	}
	
	ReturnValueWithNoError(YES, error)
}

- (BOOL)_processOperations:(NSError**)error {
	mpq_deferred_operation_t* operation = last_operation;
	while (operation) {
		// Make sure this is the current operation for hash table entry
		if (operation_hash_table[operation->primary_file_context.hash_position] != operation) {
			operation = operation->previous;
			continue;
		}
		
		if (operation->type == MPQDOAdd) {
			if ([delegate respondsToSelector:@selector(archive:willAddFile:)])
				[delegate archive:self willAddFile:operation->primary_file_context.filename];
			
			if (![self _performFileAddOperation:operation error:error]) {
				[delegate archive:self failedToAddFile:operation->primary_file_context.filename error:*error];
				return NO;
			}
			
			if ([delegate respondsToSelector:@selector(archive:didAddFile:)])
				[delegate archive:self didAddFile:operation->primary_file_context.filename];
		}
		
		operation = operation->previous;
	}
	
	ReturnValueWithNoError(YES, error)
}

- (BOOL)writeToFile:(NSString*)path atomically:(BOOL)atomically error:(NSError**)error {
	NSParameterAssert(path != nil);
	MPQDebugLog(@"writing archive to disk");
	
	// There's nothing to do if we're not modified
	if (!is_modified && archive_path && [archive_path isEqualToString:path]) {
		MPQDebugLog(@"not modified");
		ReturnValueWithNoError(YES, error)
	}
	
	// Ask the delegate if we should save
	if ([delegate respondsToSelector:@selector(archiveShouldSave:)]) {
		if (![delegate archiveShouldSave:self]) {
			MPQDebugLog(@"delegate tells us to abort");
			ReturnValueWithError(NO, MPQErrorDomain, errDelegateCancelled, nil, error)
		}
	}
	
	// Tell the delegate we're about to start saving
	if ([delegate respondsToSelector:@selector(archiveWillSave:)]) [delegate archiveWillSave:self];
	
	// Manage an autorelease pool to kill all temporary objects after this is done
	NSAutoreleasePool* p = [NSAutoreleasePool new];
	
	/*
		This flag is used to indicate what needs to be done in case of error or at the end of the write operation. They are done in order from top to bottom.
		
		0x1: close archive_fd and set it to -1
		0x2: delete the file at path
		0x4: delete the file at temp_path
		0x8: set archive_fd to temp_fd
	*/
	int pFlags = 0;
	
	// Atomic file and file descriptor
	NSString* temp_path = nil;
	int temp_fd = -1;
	
	// Backup instance state in case of failure
	mpq_header_t header_backup = header;
	mpq_extended_header_t extended_header_backup = extended_header;
	off_t archive_write_offset_backup = archive_write_offset;
	off_t archive_size_backup = archive_size;
	off_t hash_table_offset_backup = hash_table_offset;
	off_t block_table_offset_backup = block_table_offset;
	
	// Multiple scenarios depending on the options and state of the instance
	if (archive_fd == -1) {
		// Create (or overwrite) a file on disk at the specified path (or at a temporary path if atomical is true)
		if (!atomically) {
			archive_fd = open([path fileSystemRepresentation], O_RDWR | O_CREAT | O_TRUNC, 0644);
			if (archive_fd == -1) {
				[p release];
				ReturnValueWithError(NO, NSPOSIXErrorDomain, errno, nil, error)
			}
			
#if defined(__APPLE__)		
			fcntl(archive_fd, F_NOCACHE, 1);
#endif
			
			// Close archive_fd, delete file at path
			pFlags = 0x3;
		} else {
			// Create a temporary file
			archive_fd = _MPQMakeTempFileInDirectory([path stringByDeletingLastPathComponent], &temp_path, error);
			if (archive_fd == -1) {
				MPQTransferErrorAndDrainPool(error, p);
				return NO;
			}
			
			// Close archive_fd, delete file at temp_path
			pFlags = 0x5;
		}
	} else if (atomically && is_modified) {		   
		// Can we write at the new final destination?
		if (![[NSFileManager defaultManager] isWritableFileAtPath:[path stringByDeletingLastPathComponent]]) {
			if (error) *error = [MPQError errorWithDomain:MPQErrorDomain code:errReadOnlyDestination userInfo:nil];
			goto WriteFailed;
		}
		
		// Keep archive_fd open as an extra safety until we are done, and back it up in temp_fd
		temp_fd = archive_fd;
		pFlags = 0x8;
		
		// Create a temporary file
		archive_fd = _MPQMakeTempFileInDirectory([path stringByDeletingLastPathComponent], &temp_path, error);
		if (archive_fd == -1) goto WriteFailed;
		
		// Close up the file descriptor and copy the existing archive at temp_path. It someone manages to sneak in and drop a file there in-between, boo.
		close(archive_fd);
		
		// Copy the archive to temp_path
		if (!_MPQFSCopy(temp_path, archive_path, error)) goto WriteFailed;
		
		// Delete file at temp_path
		pFlags |= 0x4;
		
		// Open the work copy
		archive_fd = open([temp_path fileSystemRepresentation], O_RDWR, 0644);
		if (archive_fd == -1) {
			if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
			goto WriteFailed;
		}
		
#if defined(__APPLE__)		
		fcntl(archive_fd, F_NOCACHE, 1);
#endif
		
		// Close archive_fd
		pFlags |= 0x1;
	} else {
		// We are saving normally, and we have a file

		// The path parameter might be different from archive_path (save as)
		if (![archive_path isEqualToString:path]) {
			// Keep archive_fd open as an extra safety until we are done, and back it up in temp_fd
			temp_fd = archive_fd;

			// Copy the archive to path
			if (!_MPQFSCopy(path, archive_path, error)) {
				archive_fd = temp_fd;
				MPQTransferErrorAndDrainPool(error, p);
				return NO;
			}
						
			// Open the copy, fail if it does not exists
			archive_fd = open([path fileSystemRepresentation], O_RDWR, 0);
			if (archive_fd == -1) {
				archive_fd = temp_fd;
				[p release];
				ReturnValueWithError(NO, NSPOSIXErrorDomain, errno, nil, error)
			}
			
#if defined(__APPLE__)		
			fcntl(archive_fd, F_NOCACHE, 1);
#endif
			
			// If the archive is not modified, we're done
			if (!is_modified) goto FinalizeWrite;
						
			// Close archive_fd, delete file at path, set archive_fd to temp_fd
			pFlags |= 0xB;
		} else {
			// This is regular saving. Just make sure we can write.
			if (is_read_only) {
				[p release];
				ReturnValueWithError(NO, MPQErrorDomain, errReadOnlyArchive, nil, error)
			}
		}
	}
	
	// Write out the listfile
	if (save_listfile) if (![self _addListfileToArchive:error]) goto WriteFailed;
	
	// Delete the weak signature if there is one
	if (weak_signature_hash_entry) {
		uint32_t signature_hash_position = [self findHashPosition:kSignatureEncryptionKey locale:MPQNeutral error:error];
		if (signature_hash_position == 0xFFFFFFFF) goto WriteFailed;
		if (![self deleteFileAtPosition:signature_hash_position error:error]) goto WriteFailed;
		weak_signature_hash_entry = NULL;
	}
	
	// Delete the attributes file right now
	if (![self deleteFile:kAttributesFilename locale:MPQNeutral error:error])
		if (![[*error domain] isEqualToString:MPQErrorDomain] || ([[*error domain] isEqualToString:MPQErrorDomain] && [*error code] != errHashTableEntryNotFound)) goto WriteFailed;
	
	MPQDebugLog(@"processing deferred operations...");
	if (![self _processOperations:error]) goto WriteFailed;
	
	// Optimize the block table by removing any empty entries
	uint32_t block_entry_index = 0;
	uint32_t free_block_entry_index = 0xFFFFFFFF;
	mpq_attributes_header_t* attributes = (mpq_attributes_header_t*)attributes_data;
	while (block_entry_index < header.block_table_length) {
		mpq_block_table_entry_t* block_table_entry = block_table + block_entry_index;
		
		// If there is a free block table entry available, move the current entry into it, empty the current entry and mark it as the first empty entry
		if (!(block_table_entry->size == 0 && block_table_entry->archived_size == 0 && block_table_entry->flags == 0) && free_block_entry_index != 0xFFFFFFFF) {
			memcpy(block_table + free_block_entry_index, block_table + block_entry_index, sizeof(mpq_block_table_entry_t));
			memset(block_table + block_entry_index, 0, sizeof(mpq_block_table_entry_t));
			
			// Scan the hash table for the entry using the block table entry we just moved
			uint32_t hash_entry_index = 0;
			while (hash_entry_index < header.hash_table_length) {
				mpq_hash_table_entry_t* hash_table_entry = hash_table + hash_entry_index;
				if (hash_table_entry->block_table_index == block_entry_index) {
					hash_table_entry->block_table_index = free_block_entry_index;
					break;
				}
				hash_entry_index++;
			}
			
			// Attributes
			if (attributes_data) {
				size_t currentOffset = sizeof(mpq_attributes_header_t);
				mpq_file_attribute_t* attribute = mpq_file_attributes;
				while (attribute->flag != 0) {
					if ((attributes->attributes & attribute->flag)) {
						memcpy(BUFFER_OFFSET(attributes_data, currentOffset + attribute->size * free_block_entry_index), 
							   BUFFER_OFFSET(attributes_data, currentOffset + attribute->size * block_entry_index), 
							   attribute->size);
						memset(BUFFER_OFFSET(attributes_data, currentOffset + attribute->size * block_entry_index), 0, attribute->size);
						currentOffset += attribute->size * header.block_table_length;
					}
					attribute++;
				}
			}
			
			free_block_entry_index++;
		} else if ((block_table_entry->size == 0 && block_table_entry->archived_size == 0 && block_table_entry->flags == 0) && free_block_entry_index == 0xFFFFFFFF) {
			free_block_entry_index = block_entry_index;
		}
		
		block_entry_index++;
	}
	
	// Write the file attributes
	if (attributes_data) {
		NSData* attributes_data_object = [NSData dataWithBytesNoCopy:attributes_data length:attributes_data_size freeWhenDone:NO];
		NSDictionary* params = [NSDictionary dictionaryWithObjectsAndKeys: 
								[NSNumber numberWithUnsignedShort:MPQNeutral], MPQFileLocale,
								[NSNumber numberWithUnsignedInt:MPQFileCompressed], MPQFileFlags,
								[NSNumber numberWithBool:YES], MPQOverwrite,
								nil];
		if (![self addFileWithData:attributes_data_object filename:kAttributesFilename parameters:params error:error]) goto WriteFailed;
		
		// Run the operations loop again, should only have one entry anyways
		if (![self _processOperations:error]) goto WriteFailed;
	}
	
	// We can cut the block table at free_block_entry_index
	uint32_t old_block_table_length = header.block_table_length;
	header.block_table_length = free_block_entry_index;
	
	// We can now compute the exact archive size and resize the archive file
	off_t new_archive_size = archive_write_offset + [self _computeSizeOfStructuralTables];
	if (![self _truncateArchiveWithDelta:(new_archive_size - archive_size) error:error]) goto WriteFailed;
	
	// NOTE: if the archive had a strong signature, _truncateArchiveWithDelta:error: has blown it away
	
	// Write the structural tables
	if (![self _writeStructuralTables:error]) goto WriteFailed;
	
	// Restore the block table length as it was before the optimization process to not waste the allocated memory
	header.block_table_length = old_block_table_length;
	
	// We need to do extra work for an atomic write
	if (atomically) {
		/*
		This flag is used to indicate what needs to be done in case of error or at the end of the write operation. They are done in order from top to bottom.
		
		0x1: close archive_fd and set it to -1
		0x2: delete the file at path
		0x4: delete the file at temp_path
		0x8: set archive_fd to temp_fd
		*/
		
		// Close the work file and the original
		close(temp_fd);
		temp_fd = -1;
		
		close(archive_fd);
		archive_fd = -1;
		pFlags &= ~0x1;

		// Put the work file in place
		if (!_MPQFSMove(path, temp_path, error)) {
			// Re-open the original (hope it works...)
			if (is_read_only) archive_fd = open([archive_path fileSystemRepresentation], O_RDONLY, 0644);
			else archive_fd = open([archive_path fileSystemRepresentation], O_RDWR, 0644);
			
			// If we failed to re-open the original file, we're owned. Otherwise, re-apply the NOCACHE policy
			if (archive_fd == -1) archive_path = nil;
#if defined(__APPLE__)		
			else fcntl(archive_fd, F_NOCACHE, 1);
#endif
			
			goto WriteFailed;
		}
		
		pFlags &= ~0x4;

		// Open the new file
		archive_fd = open([path fileSystemRepresentation], O_RDWR, 0644);
		if (archive_fd == -1) {
			// WE JUST GOT OWNED
			archive_path = nil;
			if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
			goto WriteFailed;
		}
		
#if defined(__APPLE__)		
		fcntl(archive_fd, F_NOCACHE, 1);
#endif
	} else if (temp_fd != -1 && ![archive_path isEqualToString:path]) {
		// Close the original file descriptor which has been backed in temp_fd
		close(temp_fd);
	}
	
	// All operations have been done and we're not going to fail, flush all DOs
	[self _flushDOS];
	
FinalizeWrite:
	// In all cases, path is now the valid archive path
	[archive_path release];
	archive_path = [path copy];
	
	// In all cases, we are not read-write and not modified
	is_read_only = NO;
	is_modified = NO;
	
	// Page the delegate to tell it that we're done
	if ([delegate respondsToSelector:@selector(archiveDidSave:)]) [delegate archiveDidSave:self];
	
	// We're done!
	[p release];
	ReturnValueWithNoError(YES, error)

WriteFailed:
	if (pFlags & 0x1) {
		close(archive_fd);
		archive_fd = -1;
	}
	if (pFlags & 0x2) [[NSFileManager defaultManager] removeFileAtPath:path handler:nil];
	if (pFlags & 0x4) [[NSFileManager defaultManager] removeFileAtPath:temp_path handler:nil];
	if (pFlags & 0x8) archive_fd = temp_fd;
	
	// TODO: we should attempt to re-write the structural tables if they were overwritten
	
	// Restore the instance's state as it was pre-write if we were atomical or writing elsewhere
	if (atomically || ![archive_path isEqualToString:path]) {
		header = header_backup;
		extended_header = extended_header_backup;
		archive_write_offset = archive_write_offset_backup;
		archive_size = archive_size_backup;
		hash_table_offset = hash_table_offset_backup;
		block_table_offset = block_table_offset_backup;
	} else {
		// Whatever is done is done for good, and whatever else, well, too bad because the archive is likely dead anyways
		[self _flushDOS];
	}
	
	MPQDebugLog(@"writeToFile failed");
	
	if (error) [*error retain];
	[p release];
	if (error) {
		if (*error == nil) *error = [MPQError errorWithDomain:MPQErrorDomain code:errUnknown userInfo:NULL];
		else [*error autorelease];
	}
	
	return NO;
}

@end
