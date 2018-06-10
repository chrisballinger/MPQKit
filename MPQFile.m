//
//  MPQFile.m
//  MPQKit
//
//  Created by Jean-Francois Roy on Mon Sep 30 2002.
//  Copyright (c) 2002-2007 MacStorm. All rights reserved.
//

#import <fcntl.h>
#import <unistd.h>
#import <zlib.h>
#import <aio.h>

#import "MPQErrors.h"
#import "MPQByteOrder.h"
#import "MPQCryptography.h"
#import "MPQArchive.h"
#import "MPQFile.h"

#import "mpqdebug.h"
#import "PHSErrorMacros.h"

#import "SCompression.h"
#import "NSDateNTFSAdditions.h"

#if defined(GNUSTEP)
@interface NSError(GSCategories)
+ (NSError*)_last;
@end
#endif

#define BUFFER_OFFSET(buffer, bytes) ((uint8_t*)buffer + (bytes))


@interface MPQArchive (MPQFilePrivate)
- (void)decreaseOpenFileCount_:(uint32_t)position;
- (void)increaseOpenFileCount_:(uint32_t)position;
@end

@implementation MPQArchive (MPQFilePrivate)

- (void)decreaseOpenFileCount_:(uint32_t)position {
    open_file_count--;
    (open_file_count_table[position])--;
}

- (void)increaseOpenFileCount_:(uint32_t)position {
    open_file_count++;
    (open_file_count_table[position])++;
}

@end

#pragma mark -
@implementation MPQFile (MPQFileAttributes)

+ (id)getCRC:(NSData*)data {
    return @(MPQSwapInt32LittleToHost(*((uint32_t*)data.bytes)));
}

+ (id)getCreationDate:(NSData*)data {
    return [NSDate dateWithNTFSFiletime:MPQSwapInt64LittleToHost(*((u_int64_t*)data.bytes))];
}

+ (id)getMD5:(NSData*)data {
    return data;
}

@end

#pragma mark -
@implementation MPQFile

- (instancetype)init {
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (instancetype)initForFile:(NSDictionary*)descriptor error:(NSError**)error {
    if (descriptor == nil) {
        return nil;
    }
    
    if ([self isMemberOfClass:[MPQFile class]]) {
        [self doesNotRecognizeSelector:_cmd];
        ReturnFromInitWithError(MPQErrorDomain, errInvalidClass, nil, error)
    }
    
    self = [super init];
    if (!self)
        return nil;
    
    filename = descriptor[@"Filename"];
    hash_position = [descriptor[@"Position"] unsignedIntValue];
    file_pointer = 0;
    
    parent = descriptor[@"Parent"];
    NSAssert(parent, @"Invalid parent archive reference");
    
    hash_entry = *(mpq_hash_table_entry_t*)[descriptor[@"HashTableEntry"] pointerValue];
    block_entry = *(mpq_block_table_entry_t*)[descriptor[@"BlockTableEntry"] pointerValue];
    
    _checkSectorAdlers = YES;
    
    [parent increaseOpenFileCount_:hash_position];
    return self;
}

- (void)dealloc {
    [parent decreaseOpenFileCount_:hash_position];    
}

- (NSString*)name {
    return filename;
}

- (uint32_t)length {
    return block_entry.size;
}

- (NSDictionary*)fileInfo {
    return [parent fileInfoForPosition:hash_position error:NULL];
}

- (NSDictionary*)fileInfo:(NSError**)error {
    return [parent fileInfoForPosition:hash_position error:error];
}

- (uint32_t)seekToFileOffset:(off_t)offset {
    return [self seekToFileOffset:offset mode:MPQFileStart error:NULL];
}

- (uint32_t)seekToFileOffset:(off_t)offset error:(NSError**)error {
    return [self seekToFileOffset:offset mode:MPQFileStart error:error];
}

- (uint32_t)seekToFileOffset:(off_t)offset mode:(MPQFileDisplacementMode)mode {
    return [self seekToFileOffset:offset mode:mode error:NULL];
}

- (uint32_t)seekToFileOffset:(off_t)offset mode:(MPQFileDisplacementMode)mode error:(NSError**)error { 
    off_t new_offset;
    
    switch (mode) {
        case MPQFileStart:
            new_offset = offset;
            break;
        case MPQFileCurrent:
            new_offset = file_pointer + offset;
            break;
        case MPQFileEnd:
            new_offset = [self length] - offset;
            break;
        default:
            ReturnValueWithError(-1, MPQErrorDomain, errInvalidDisplacementMode, nil, error)
    }

    if (new_offset > [self length])
        ReturnValueWithError(-1, MPQErrorDomain, errInvalidOffset, nil, error)
    if (new_offset < 0)
        ReturnValueWithError(-1, MPQErrorDomain, errInvalidOffset, nil, error)
    
    // Explicit cast is OK here, MPQ file sizes are 32-bit
    file_pointer = (uint32_t)new_offset;
    return file_pointer;
}

- (uint32_t)offsetInFile {
    return file_pointer;
}

- (BOOL)eof {
    return (file_pointer >= [self length]);
}

- (BOOL)liveSectorChecksumValidatation {
    return _checkSectorAdlers;
}

- (void)setLiveSectorChecksumValidation:(BOOL)flag {
    _checkSectorAdlers = flag;
}

- (NSData*)copyDataOfLength:(uint32_t)length {
    return [self copyDataOfLength:length error:NULL];
}

- (NSData*)copyDataOfLength:(uint32_t)length error:(NSError**)error {
    NSMutableData* data = [[NSMutableData alloc] initWithLength:length];
    ssize_t bytes_read = [self read:data.mutableBytes size:length error:error];
    if (bytes_read == -1) {
        return nil;
    }
    
    data.length = bytes_read;
    return data;
}

- (NSData*)copyDataToEndOfFile {
    return [self copyDataOfLength:[self length] error:NULL];
}

- (NSData*)copyDataToEndOfFile:(NSError**)error {
    return [self copyDataOfLength:[self length] error:error];
}

- (NSData*)getDataOfLength:(uint32_t)length {
    return [self copyDataOfLength:length error:NULL];
}

- (NSData*)getDataOfLength:(uint32_t)length error:(NSError**)error {
    return [self copyDataOfLength:length error:error];
}

- (NSData*)getDataToEndOfFile {
    return [self copyDataToEndOfFile:NULL];
}

- (NSData*)getDataToEndOfFile:(NSError**)error {
    return [self copyDataToEndOfFile:error];
}

- (ssize_t)read:(void*)buf size:(size_t)size error:(NSError**)error {
    [self doesNotRecognizeSelector:_cmd];
    return -1;
}

- (BOOL)writeToFile:(NSString*)path atomically:(BOOL)atomically {
    return [self writeToFile:path atomically:atomically error:NULL];
}

- (BOOL)writeToFile:(NSString*)path atomically:(BOOL)atomically error:(NSError**)error {
    uint32_t old = file_pointer;
    file_pointer = 0;
    
    NSData* fileData = [self copyDataToEndOfFile];
    BOOL result = [fileData writeToFile:path options:(atomically) ? NSAtomicWrite : 0 error:error];
    
    file_pointer = old;
    return result;
}

@end

#pragma mark -

@interface MPQFileDataSource : MPQFile {
    MPQDataSource* dataSource;
}
@end

@implementation MPQFileDataSource

- (id)initForFile:(NSDictionary*)descriptor error:(NSError**)error {
    self = [super initForFile:descriptor error:error];
    if (!self)
        return nil;
    
    dataSource = [(MPQDataSourceProxy*)descriptor[@"DataSourceProxy"] createActualDataSource:error];
    NSAssert(dataSource, @"Invalid data object");
    
    return self;
}

- (uint32_t)length {
    off_t length = [dataSource length:NULL];
    if (length == -1)
        return 0;
    
    // This may not be necessary (if this is what the typecast will do)
    if (length > UINT32_MAX)
        return UINT32_MAX;
    return (uint32_t)length;
}

- (ssize_t)read:(void*)buf size:(size_t)size error:(NSError**)error {
    if (file_pointer >= [self length])
        return 0;
    
    size = MIN(size, [self length] - file_pointer);
    if (size == 0)
        return 0;
    
    ssize_t read_bytes = [dataSource pread:buf size:size offset:file_pointer error:error];
    if (read_bytes == -1)
        return -1;
    
    // Explicit cast is OK here, MPQ file sizes are 32-bit
    file_pointer += (uint32_t)read_bytes;
    return read_bytes;
}

- (NSData*)_copyRawSector:(uint32_t)index error:(NSError**)error {
    ReturnValueWithError(nil, MPQErrorDomain, errInvalidOperation, nil, error);
}

@end

#pragma mark -

@interface MPQFileConcreteMPQ : MPQFile {
    int archive_fd;
    off_t file_archive_offset;
    
    uint32_t encryption_key;
    
    uint32_t sector_size_shift;
    uint32_t full_sector_size;
    
    uint32_t sector_table_length;
    uint32_t* sector_table;
    uint32_t* _sector_adlers;
    
    void* buffer_;
    void* read_buffer;
    void* data_buffer;
}
@end

@implementation MPQFileConcreteMPQ

- (id)initForFile:(NSDictionary*)descriptor error:(NSError**)error {
    self = [super initForFile:descriptor error:error];
    if (!self)
        return nil;
    
    archive_fd = [descriptor[@"FileDescriptor"] intValue];
    NSAssert(archive_fd >= 0, @"Invalid archive file descriptor");
    
    sector_size_shift = [descriptor[@"SectorSizeShift"] unsignedIntValue];
    full_sector_size = MPQ_BASE_SECTOR_SIZE << sector_size_shift;
    NSAssert(sector_size_shift > 0, @"Invalid sector size shift");
    
    file_archive_offset = [descriptor[@"FileArchiveOffset"] longLongValue];
    encryption_key = [descriptor[@"EncryptionKey"] unsignedIntValue];
    
    sector_table_length = [descriptor[@"SectorTableLength"] unsignedIntValue];
    sector_table = [descriptor[@"SectorTable"] pointerValue];
    if (block_entry.flags & (MPQFileCompressed | MPQFileDiabloCompressed)) {
        NSAssert(sector_table_length > 0, @"Invalid sector table length");
        NSAssert(sector_table, @"Invalid sector table");
    } else if (sector_table_length > 1) {
        // Synthesize a sector table to have a unified read method
        sector_table = malloc(sizeof(uint32_t) * sector_table_length);
        for (uint32_t sector_index = 0; sector_index < sector_table_length - 1; sector_index++) sector_table[sector_index] = sector_index * full_sector_size;
        sector_table[sector_table_length - 1] = block_entry.size;
        assert(sector_table[sector_table_length - 1] - sector_table[sector_table_length - 2] <= full_sector_size);
    } else
        sector_table = NULL;
    
    _sector_adlers = NULL;
    
    // Memory for compression/decompression operations
    buffer_ = valloc(full_sector_size + (full_sector_size << 4));
    if (!buffer_)
        ReturnFromInitWithError(MPQErrorDomain, errOutOfMemory, nil, error)
    
    read_buffer = buffer_;
    data_buffer = BUFFER_OFFSET(buffer_, full_sector_size << 4);
    
    return self;
}

- (void)dealloc {
    if (buffer_)
        free(buffer_);
    if (!(block_entry.flags & (MPQFileCompressed | MPQFileDiabloCompressed)) && sector_table)
        free(sector_table);
    if (_sector_adlers)
        free(_sector_adlers);
}

- (ssize_t)_readSectors:(void*)buf range:(NSRange)which keeping:(NSRange)bytesToKeep error:(NSError**)error {
    int perr = 0;
    int stage = 0;
    
    // Make sure the first sector is within bounds. Remember, sector_table_length - 2 is the index of the last sector.
    if (which.location > sector_table_length - 2)
        ReturnValueWithError(-1, MPQErrorDomain, errOutOfBounds, nil, error);
    
    // Make sure the last sector is within bounds.
    // which.location + which.length - 1 is the index of the last sector to be read.
    if (which.location + which.length > sector_table_length - 1)
        ReturnValueWithError(-1, MPQErrorDomain, errOutOfBounds, nil, error);
    
    // Current offset into buf
    size_t data_offset = 0;
    
    // Read state
    uint32_t last_sector = sector_table_length - 2;
    uint32_t decompressed_sector_size = full_sector_size;
    // Explicit cast is OK here, MPQ file sizes are 32-bit
    size_t bytes_left = bytesToKeep.length;
    uint32_t read_size = full_sector_size << 4;
    if (read_size > block_entry.archived_size) read_size = full_sector_size;
    ssize_t bytes_read;
    
    BOOL encrypted = (block_entry.flags & MPQFileEncrypted) ? YES : NO;
    
    // If live sector checksum validation is enabled, read the sector adlers (if we have them)
    if (_checkSectorAdlers && (block_entry.flags & MPQFileHasSectorAdlers) && !_sector_adlers) {
        size_t sector_adlers_size = sector_table[sector_table_length] - sector_table[sector_table_length - 1];
        if (sector_adlers_size) {
            void* compressed_adlers = malloc(sector_adlers_size);
            if (!compressed_adlers)
                ReturnValueWithError(-1, MPQErrorDomain, errOutOfMemory, nil, error)
            
            bytes_read = pread(archive_fd, compressed_adlers, sector_adlers_size, file_archive_offset + sector_table[sector_table_length - 1]);
            if (bytes_read == -1) {
                free(compressed_adlers);
                ReturnValueWithPOSIXError(-1, nil, error)
            }
            if ((size_t)bytes_read < sector_adlers_size) {
                free(compressed_adlers);
                ReturnValueWithError(-1, MPQErrorDomain, errEndOfFile, nil, error)
            }
            
            uint32_t decompressed_adlers_size = (sector_table_length - 1) * (uint32_t)sizeof(uint32_t);
            _sector_adlers = malloc(decompressed_adlers_size);
            if (!compressed_adlers) {
                free(compressed_adlers);
                ReturnValueWithError(-1, MPQErrorDomain, errOutOfMemory, nil, error)
            }
            
            perr = SCompDecompress(_sector_adlers, &decompressed_adlers_size, compressed_adlers, (uint32_t)sector_adlers_size);
            free(compressed_adlers);
            if (perr == 0)
                ReturnValueWithError(-1, MPQErrorDomain, errInvalidSectorChecksumData, nil, error)
        }
    }
    
#if defined(MPQFILE_PREAD_CHECK)
    // memcmp and decompression buffer
    void* memcmp_buffer = malloc(full_sector_size << 1);
#endif
    
    // This will keep track of which aiocb we're going to read from (and suspend on) next
    uint8_t current_iocb = 0;
    
    // Keep track of left-overs
    size_t bytes_available[2] = {0, 0};
    
    // Explicit cast is OK here, there cannot be more sectors than the 32-bit integer range
    uint32_t current_sector = (uint32_t)which.location;
    uint32_t last_needed_sector_plus_one = (uint32_t)(which.location + which.length);
    uint32_t last_needed_sector = last_needed_sector_plus_one - 1;
    while (current_sector < last_needed_sector_plus_one) {
        bytes_read = pread(archive_fd, read_buffer, read_size, file_archive_offset + sector_table[current_sector]);
        if (bytes_read == -1) {
            perr = -1;
            if (error)
                *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            goto ErrorExit;
        } else if (bytes_read == 0) {
            if (error)
                *error = [MPQError errorWithDomain:MPQErrorDomain code:errEndOfFile userInfo:nil];
            goto ErrorExit;
        }
        
        void* sector_buffer = read_buffer;
        uint32_t sector_buffer_offset = 0;
        bytes_available[current_iocb] = bytes_read;
        
        // Compute sector_size for the first iteration
        uint32_t sector_size = sector_table[current_sector + 1] - sector_table[current_sector];
        
        // Process as many sectors as possible with the current aio buffer
        stage = 2;
        while (bytes_available[current_iocb] >= sector_size) {
#if defined(MPQFILE_PREAD_CHECK)
            NSLog(@"Doing pread check...");
            perr = pread(archive_fd, memcmp_buffer, sector_size, file_archive_offset + sector_table[current_sector]);
            if (perr == -1) {
                if (error)
                    *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
                goto ErrorExit;
            }
            
            perr = memcmp(memcmp_buffer, sector_buffer + sector_buffer_offset, sector_size);
            if (perr) {
                NSLog(@"memcmp failed!");
                perr = 0;
                if (error)
                    *error = [MPQError errorWithDomain:MPQErrorDomain code:0xBABE userInfo:nil];
                goto ErrorExit;
            }
            
            sector_buffer = memcmp_buffer;
            sector_buffer_offset = 0;
#endif
            // If we have sector adlers, checksum the sector and verify
            if (_sector_adlers) {
                uLong adler = adler32(0L, BUFFER_OFFSET(sector_buffer, sector_buffer_offset), sector_size);
                if (adler != (uLong)_sector_adlers[current_sector]) {
                    if (error) {
                        NSDictionary* userInfo = [[NSDictionary alloc] initWithObjectsAndKeys:
                            [self fileInfo], MPQErrorFileInfo, 
                            @(current_sector), MPQErrorSectorIndex, 
                            @(adler), MPQErrorComputedSectorChecksum, 
                            @(_sector_adlers[current_sector]), MPQErrorExpectedSectorChecksum, 
                            nil];
                        *error = [MPQError errorWithDomain:MPQErrorDomain code:errInvalidSectorChecksum userInfo:userInfo];
                    }
                    goto ErrorExit;
                }
            }
            
            // If the file is encrypted, decrypt the sector
            if (encrypted)
                mpq_decrypt(BUFFER_OFFSET(sector_buffer, sector_buffer_offset), sector_size, encryption_key + current_sector, NO);
            
            // if we're processing the last sector of the file, we need to adjust its decompressed size
            if (current_sector == last_sector)
                decompressed_sector_size = block_entry.size - (last_sector * full_sector_size);
            
            // normally we just decompress into the client buffer at the proper offset
            void* decompression_destination_buffer = BUFFER_OFFSET(buf, data_offset);
            
            // however if we're processing the last needed sector or if the client buffer is just too small, we need to use a temporary buffer
            if (current_sector == last_needed_sector || bytesToKeep.length < decompressed_sector_size)
                decompression_destination_buffer = data_buffer;
            
            // Use the proper decompression method
            if (block_entry.flags & MPQFileCompressed) {
                perr = SCompDecompress(decompression_destination_buffer, &decompressed_sector_size, BUFFER_OFFSET(sector_buffer, sector_buffer_offset), sector_size);
                if (perr == 0) {
                    if (error)
                        *error = [MPQError errorWithDomain:MPQErrorDomain code:errDecompressionFailed userInfo:nil];
                    goto ErrorExit;
                }
            } else if ((block_entry.flags & MPQFileDiabloCompressed) && (sector_size < decompressed_sector_size)) {
                // FIXME: handle Decompress_pklib errors
                Decompress_pklib(decompression_destination_buffer, &decompressed_sector_size, BUFFER_OFFSET(sector_buffer, sector_buffer_offset), sector_size);
            } else {
                decompressed_sector_size = sector_size;
                memcpy(decompression_destination_buffer, BUFFER_OFFSET(sector_buffer, sector_buffer_offset), decompressed_sector_size);
            }
            
            // need to handle the first and last needed sectors a bit differently
            if (current_sector == which.location) {
                assert(data_offset == 0);
                
                // determime how many bytes we need to skip from the beginning of the sector (bytesToKeep is w/r to the whole file)
                // explicit cast is OK here, sector sizes are 32-bit
                uint32_t bytes_to_skip = (uint32_t)bytesToKeep.location % full_sector_size;
                
                // determine how many bytes we need to copy (either the full sector minus skipped bytes, or just the number of bytes left if we only need one sector)
                size_t bytes_to_copy = MIN(bytes_left, decompressed_sector_size - bytes_to_skip);
                
                // must use memmove because decompression_destination_buffer may be == buf
                memmove(buf, BUFFER_OFFSET(decompression_destination_buffer, bytes_to_skip), bytes_to_copy);
                data_offset += bytes_to_copy;
            } else if (current_sector == last_needed_sector) {
                memcpy(BUFFER_OFFSET(buf, data_offset), decompression_destination_buffer, bytes_left);
                data_offset += bytes_left;
            } else
                data_offset += decompressed_sector_size;
            
            // Update bytes_left
            assert(data_offset <= bytesToKeep.length);
            bytes_left = (data_offset > bytesToKeep.length) ? 0 : bytesToKeep.length - data_offset;
            
            // Move on the the next sector
            current_sector++;
            if (current_sector == last_needed_sector_plus_one)
                break;
            
            // Update the number of bytes available from the current aio buffer and update sector_size for the next sector
            bytes_available[current_iocb] -= sector_size;
            sector_buffer_offset += sector_size;
            sector_size = sector_table[current_sector + 1] - sector_table[current_sector];
        }
        
        // Immediatly exit if we're done
        if (current_sector == last_needed_sector_plus_one)
            break;
    }
    
#if defined(MPQFILE_PREAD_CHECK)
    free(memcmp_buffer);
#endif
    
    // Make sure we respected our contract
    assert(bytes_left == 0);
    assert(data_offset == bytesToKeep.length);
    return data_offset;
        
ErrorExit:
    MPQDebugLog(@"%@ error occured at stage %d in readSectors", (error) ? (*error).localizedDescription : nil, stage);
    if (perr == -1)
        MPQDebugLog(@"errno is %d", errno);
    
#if defined(MPQFILE_PREAD_CHECK)
    free(memcmp_buffer);
#endif
    
    return -1;
}

- (ssize_t)read:(void*)buf size:(size_t)size error:(NSError**)error {
    if (file_pointer >= block_entry.size)
        return 0;
    
    size = MIN(size, block_entry.size - file_pointer);
    if (size == 0)
        return 0;
    
    uint32_t location = file_pointer / full_sector_size;
    NSRange sectors_range = NSMakeRange(location, ((file_pointer + size + full_sector_size - 1) / full_sector_size) - location);
    NSRange data_range = NSMakeRange(file_pointer, size);
        
    ssize_t bytes_read = [self _readSectors:buf range:sectors_range keeping:data_range error:error];
    // Explicit cast is OK here, MPQ file sizes are 32-bit
    if (bytes_read != -1)
        file_pointer += (uint32_t)bytes_read;
    return bytes_read;
}

- (NSData*)_copyRawSector:(uint32_t)index error:(NSError**)error {
    if (index > sector_table_length - 2)
        ReturnValueWithError(nil, MPQErrorDomain, errOutOfBounds, nil, error)
    
    size_t sector_size = sector_table[index + 1] - sector_table[index];
    ssize_t bytes_read = pread(archive_fd, read_buffer, sector_size, file_archive_offset + sector_table[index]);
    if (bytes_read == -1)
        ReturnValueWithPOSIXError(nil, nil, error)
    if ((size_t)bytes_read < sector_size)
        ReturnValueWithError(nil, MPQErrorDomain, errIO, nil, error)
    
    return [[NSData alloc] initWithBytes:read_buffer length:sector_size];
}

@end

#pragma mark -

@interface MPQFileConcreteMPQOneSector : MPQFile {
    int archive_fd;
    off_t file_archive_offset;
    uint32_t encryption_key;
    
    void* data_cache_;
}
@end

@implementation MPQFileConcreteMPQOneSector

- (id)initForFile:(NSDictionary*)descriptor error:(NSError**)error {
    self = [super initForFile:descriptor error:error];
    if (!self)
        return nil;
    
    archive_fd = [descriptor[@"FileDescriptor"] intValue];
    NSAssert(archive_fd, @"Invalid archive file descriptor");
    
    file_archive_offset = [descriptor[@"FileArchiveOffset"] longLongValue];
    encryption_key = [descriptor[@"EncryptionKey"] unsignedIntValue];
    
    return self;
}

- (void)dealloc {
    if (data_cache_)
        free(data_cache_);
}

- (ssize_t)read:(void*)buf size:(size_t)size error:(NSError**)error {
    if (file_pointer >= block_entry.size)
        return 0;
    
    size = MIN(size, block_entry.size - file_pointer);
    if (size == 0)
        return 0;

    // If we haven't decompressed the file already, do it now
    // TODO: stream decompression
    if (!data_cache_) {
        data_cache_ = malloc(block_entry.size);
        if (!data_cache_)
            ReturnValueWithError(-1, MPQErrorDomain, errOutOfMemory, nil, error)
        
        void* read_buffer = malloc(block_entry.archived_size);
        if (!read_buffer)
            ReturnValueWithError(-1, MPQErrorDomain, errOutOfMemory, nil, error)
                    
        // Read the data
        ssize_t bytes_read = pread(archive_fd, read_buffer, block_entry.archived_size, file_archive_offset);
        if (bytes_read == -1) {
            free(read_buffer);
            ReturnValueWithPOSIXError(-1, nil, error)
        }
        if ((uint32_t)bytes_read < block_entry.archived_size) {
            free(read_buffer);
            ReturnValueWithError(-1, MPQErrorDomain, errIO, nil, error)
        }
        
        // If the file is encrypted, decrypt it
        if (block_entry.flags & MPQFileEncrypted)
            mpq_decrypt(read_buffer, block_entry.archived_size, encryption_key, NO);
        
        // Decompress the file or do a straight memory copy
        uint32_t decompressed_size = block_entry.size;
        if (block_entry.flags & MPQFileCompressed) {
            if (SCompDecompress(data_cache_, &decompressed_size, read_buffer, block_entry.archived_size) == 0) {
                free(read_buffer);
                ReturnValueWithError(-1, MPQErrorDomain, errDecompressionFailed, nil, error)
            }
        } else if ((block_entry.flags & MPQFileDiabloCompressed) && (block_entry.archived_size < decompressed_size)) {
            Decompress_pklib(data_cache_, &decompressed_size, read_buffer, block_entry.archived_size);
        } else {
            memcpy(data_cache_, read_buffer, block_entry.archived_size);
            decompressed_size = block_entry.archived_size;
        }
        
        if (decompressed_size != block_entry.size) {
            free(read_buffer);
            ReturnValueWithError(-1, MPQErrorDomain, errDecompressionFailed, nil, error)
        }
        
        free(read_buffer);
    }
    
    memcpy(buf, BUFFER_OFFSET(data_cache_, file_pointer), size);
    // Explicit cast is OK here, MPQ file sizes are 32-bit
    file_pointer += (uint32_t)size;
    
    return size;
}

- (NSData*)_copyRawSector:(uint32_t)index error:(NSError**)error {
    if (index > 0)
        ReturnValueWithError(nil, MPQErrorDomain, errOutOfBounds, nil, error)
    
    void* read_buffer = malloc(block_entry.archived_size);
    if (!read_buffer)
        ReturnValueWithError(nil, MPQErrorDomain, errOutOfMemory, nil, error)
    
    ssize_t bytes_read = pread(archive_fd, read_buffer, block_entry.archived_size, file_archive_offset);
    if (bytes_read == -1) {
        free(read_buffer);
        ReturnValueWithPOSIXError(nil, nil, error)
    }
    if ((uint32_t)bytes_read < block_entry.archived_size) {
        free(read_buffer);
        ReturnValueWithError(nil, MPQErrorDomain, errIO, nil, error)
    }
    
    return [[NSData alloc] initWithBytesNoCopy:read_buffer length:block_entry.archived_size freeWhenDone:YES];
}

@end
