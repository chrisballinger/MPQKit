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
#import <sys/aio.h>

#import "MPQErrors.h"
#import "MPQCryptography.h"
#import "MPQArchive.h"
#import "MPQFile.h"

#import "mpqdebug.h"
#import "PHSErrorMacros.h"

#import "SCompression.h"
#import "NSDateNTFSAdditions.h"

#define BUFFER_OFFSET(buffer, bytes) ((uint8_t *)buffer + (bytes))

#if defined(MPQKIT_USE_AIO)
#define MPQFILE_AIO
#endif


@interface MPQArchive (MPQFilePrivate)
- (void)decreaseOpenFileCount_:(uint32_t)position;
- (void)increaseOpenFileCount_:(uint32_t)position;
@end

@implementation MPQArchive (MPQFilePrivate)

- (void)decreaseOpenFileCount_:(uint32_t)position {
    open_file_count--;
    (open_file_count_table[position])--;
    if (open_file_count == 0) [self release];
}

- (void)increaseOpenFileCount_:(uint32_t)position {
    open_file_count++;
    (open_file_count_table[position])++;
    if (open_file_count == 1) [self retain];
}

@end

#pragma mark -
@implementation MPQFile (MPQFileAttributes)

+ (id)getCRC:(NSData *)data {
    return [NSNumber numberWithUnsignedInt:CFSwapInt32LittleToHost(*((uint32_t *)[data bytes]))];
}

+ (id)getCreationDate:(NSData *)data {
    return [NSDate dateWithNTFSFiletime:CFSwapInt64LittleToHost(*((u_int64_t *)[data bytes]))];
}

+ (id)getMD5:(NSData *)data {
    return data;
}

@end

#pragma mark -
@implementation MPQFile

- (id)init {
    [self doesNotRecognizeSelector:_cmd];
    [self release];
    return nil;
}

- (id)initForFile:(NSDictionary *)descriptor error:(NSError **)error {
    if (descriptor == nil) {
        [self release];
        return nil;
    }
    
    if ([self isMemberOfClass:[MPQFile class]]) {
        [self doesNotRecognizeSelector:_cmd];
        ReturnFromInitWithError(MPQErrorDomain, errInvalidClass, nil, error)
    }
    
    self = [super init];
    if (!self) return nil;
    
    filename = [[descriptor objectForKey:@"Filename"] retain];
    hash_position = [[descriptor objectForKey:@"Position"] unsignedIntValue];
    file_pointer = 0;
    
    parent = [descriptor objectForKey:@"Parent"];
    NSAssert(parent, @"Invalid parent archive reference");
    
    hash_entry = *(mpq_hash_table_entry_t *)[[descriptor objectForKey:@"HashTableEntry"] pointerValue];
    block_entry = *(mpq_block_table_entry_t *)[[descriptor objectForKey:@"BlockTableEntry"] pointerValue];
    
    _checkSectorAdlers = NO;
    
    [parent increaseOpenFileCount_:hash_position];
    ReturnValueWithNoError(self, error)
}

- (void)dealloc {
    [filename release];
    [parent decreaseOpenFileCount_:hash_position];
    
    [super dealloc];
}

- (NSString *)name {
    return filename;
}

- (uint32_t)length {
    return block_entry.size;
}

- (NSDictionary *)fileInfo {
    return [parent fileInfoForPosition:hash_position error:nil];
}

- (NSDictionary *)fileInfo:(NSError **)error {
    return [parent fileInfoForPosition:hash_position error:error];
}

- (uint32_t)seekToFileOffset:(off_t)offset {
    return [self seekToFileOffset:offset mode:MPQFileStart error:nil];
}

- (uint32_t)seekToFileOffset:(off_t)offset error:(NSError **)error {
    return [self seekToFileOffset:offset mode:MPQFileStart error:error];
}

- (uint32_t)seekToFileOffset:(off_t)offset mode:(MPQFileDisplacementMode)mode {
    return [self seekToFileOffset:offset mode:mode error:nil];
}

- (uint32_t)seekToFileOffset:(off_t)offset mode:(MPQFileDisplacementMode)mode error:(NSError **)error { 
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

    if (new_offset > [self length]) ReturnValueWithError(-1, MPQErrorDomain, errInvalidOffset, nil, error)
    if (new_offset < 0) ReturnValueWithError(-1, MPQErrorDomain, errInvalidOffset, nil, error)
    
    // Explicit cast is OK here, MPQ file sizes are 32-bit
    file_pointer = (uint32_t)new_offset;
    ReturnValueWithNoError(file_pointer, error)
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

- (NSData *)copyDataOfLength:(uint32_t)length {
    return [self copyDataOfLength:length error:nil];
}

- (NSData *)copyDataOfLength:(uint32_t)length error:(NSError **)error {
    NSMutableData *data = [[NSMutableData alloc] initWithLength:length];
    ssize_t bytes_read = [self read:[data mutableBytes] size:length error:error];
    if (bytes_read == -1) {
        [data release];
        return nil;
    }
    
    [data setLength:bytes_read];
    return data;
}

- (NSData *)copyDataToEndOfFile {
    return [self copyDataOfLength:[self length] error:nil];
}

- (NSData *)copyDataToEndOfFile:(NSError **)error {
    return [self copyDataOfLength:[self length] error:error];
}

- (NSData *)getDataOfLength:(uint32_t)length {
    return [[self copyDataOfLength:length error:nil] autorelease];
}

- (NSData *)getDataOfLength:(uint32_t)length error:(NSError **)error {
    return [[self copyDataOfLength:length error:error] autorelease];
}

- (NSData *)getDataToEndOfFile {
    return [[self copyDataToEndOfFile:nil] autorelease];
}

- (NSData *)getDataToEndOfFile:(NSError **)error {
    return [[self copyDataToEndOfFile:error] autorelease];
}

- (ssize_t)read:(void *)buf size:(size_t)size error:(NSError **)error {
    [self doesNotRecognizeSelector:_cmd];
    return -1;
}

- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically {
    return [self writeToFile:path atomically:atomically error:nil];
}

- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically error:(NSError **)error {
    uint32_t old = file_pointer;
    file_pointer = 0;
    
    NSData *fileData = [self copyDataToEndOfFile];
    BOOL result = [fileData writeToFile:path options:(atomically) ? NSAtomicWrite : 0 error:error];
    
    file_pointer = old;
    [fileData release];
    return result;
}

@end

#pragma mark -

@interface MPQFileDataSource : MPQFile {
    MPQDataSource *dataSource;
}
@end

@implementation MPQFileDataSource

- (id)initForFile:(NSDictionary *)descriptor error:(NSError **)error {
    self = [super initForFile:descriptor error:error];
    if (!self) return nil;
    
    dataSource = [(MPQDataSourceProxy *)[descriptor objectForKey:@"DataSourceProxy"] createActualDataSource:error];
    NSAssert(dataSource, @"Invalid data object");
    
    ReturnValueWithNoError(self, error)
}

- (void)dealloc {
    [dataSource release];
    [super dealloc];
}

- (uint32_t)length {
    off_t length = [dataSource length:NULL];
    if (length == -1) return 0;
    
    // This may not be necessary (if this is what the typecast will do)
    if (length > UINT32_MAX) return UINT32_MAX;
    return (uint32_t)length;
}

- (ssize_t)read:(void *)buf size:(size_t)size error:(NSError **)error {
    if (file_pointer >= [self length]) ReturnValueWithNoError(0, error)
    
    size = MIN(size, [self length] - file_pointer);
    if (size == 0) ReturnValueWithNoError(0, error)
    
    ssize_t read_bytes = [dataSource pread:buf size:size offset:file_pointer error:error];
    if (read_bytes == -1) return -1;
    // Explicit cast is OK here, MPQ file sizes are 32-bit
    file_pointer += (uint32_t)read_bytes;
    ReturnValueWithNoError(read_bytes, error)
}

- (NSData *)_copyRawSector:(uint32_t)index error:(NSError **)error {
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
    uint32_t *sector_table;
    uint32_t *_sector_adlers;
    
    void *buffer_;
    void *read_buffer;
    void *data_buffer;
}
@end

@implementation MPQFileConcreteMPQ

- (id)initForFile:(NSDictionary *)descriptor error:(NSError **)error {
    self = [super initForFile:descriptor error:error];
    if (!self) return nil;
    
    archive_fd = [[descriptor objectForKey:@"FileDescriptor"] intValue];
    NSAssert(archive_fd >= 0, @"Invalid archive file descriptor");
    
    sector_size_shift = [[descriptor objectForKey:@"SectorSizeShift"] unsignedIntValue];
    full_sector_size = 512 << sector_size_shift;
    NSAssert(sector_size_shift > 0, @"Invalid sector size shift");
    
    file_archive_offset = [[descriptor objectForKey:@"FileArchiveOffset"] longLongValue];
    encryption_key = [[descriptor objectForKey:@"EncryptionKey"] unsignedIntValue];
    
    sector_table_length = [[descriptor objectForKey:@"SectorTableLength"] unsignedIntValue];
    sector_table = [[descriptor objectForKey:@"SectorTable"] pointerValue];
    if (block_entry.flags & (MPQFileCompressed | MPQFileDiabloCompressed)) {
        NSAssert(sector_table_length > 0, @"Invalid sector table length");
        NSAssert(sector_table, @"Invalid sector table");
    } else if (sector_table_length > 1) {
        // Synthesize a sector table to have a unified read method
        sector_table = malloc(sizeof(uint32_t) * sector_table_length);
        for (uint32_t sector_index = 0; sector_index < sector_table_length - 1; sector_index++) sector_table[sector_index] = sector_index * full_sector_size;
        sector_table[sector_table_length - 1] = block_entry.size;
        assert(sector_table[sector_table_length - 1] - sector_table[sector_table_length - 2] <= full_sector_size);
    } else sector_table = NULL;
    
    _sector_adlers = NULL;
    
    // Memory for compression/decompression operations
#if defined(MPQFILE_AIO)
    buffer_ = valloc(full_sector_size * 7);
#else
    buffer_ = valloc(full_sector_size + (full_sector_size << 4));
#endif
    if (!buffer_) ReturnFromInitWithError(MPQErrorDomain, errOutOfMemory, nil, error)
    
    read_buffer = buffer_;
    data_buffer = BUFFER_OFFSET(buffer_, full_sector_size << 4);
    
    ReturnValueWithNoError(self, error)
}

- (void)dealloc {
    if (buffer_) free(buffer_);
    if (!(block_entry.flags & (MPQFileCompressed | MPQFileDiabloCompressed)) && sector_table) free(sector_table);
    if (_sector_adlers) free(_sector_adlers);
    [super dealloc];
}

- (ssize_t)_readSectors:(void *)buf range:(NSRange)which keeping:(NSRange)bytesToKeep error:(NSError **)error {
    int perr = 0;
    int stage = 0;
    
    // Make sure the first sector is within bounds. Remember, sector_table_length - 2 is the index of the last sector.
    if (which.location > sector_table_length - 2) ReturnValueWithError(-1, MPQErrorDomain, errOutOfBounds, nil, error);
    
    // Make sure the last sector is within bounds.
    // which.location + which.length - 1 is the index of the last sector to be read.
    if (which.location + which.length > sector_table_length - 1) ReturnValueWithError(-1, MPQErrorDomain, errOutOfBounds, nil, error);
    
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
        // Quick sanity check
        size_t sector_adlers_size = (sector_table_length - 1) * sizeof(uint32_t);
        if ((sector_table[sector_table_length] - sector_table[sector_table_length - 1]) != sector_adlers_size) ReturnValueWithError(-1, MPQErrorDomain, errInvalidSectorChecksumData, nil, error)
        _sector_adlers = malloc(sector_adlers_size);
        if (!_sector_adlers) ReturnValueWithError(-1, MPQErrorDomain, errOutOfMemory, nil, error)
        bytes_read = pread(archive_fd, _sector_adlers, sector_adlers_size, file_archive_offset + sector_table[sector_table_length - 1]);
        if (bytes_read == -1) ReturnValueWithPOSIXError(-1, nil, error)
        if ((size_t)bytes_read < sector_adlers_size) ReturnValueWithError(-1, MPQErrorDomain, errEndOfFile, nil, error)
    }
    
#if defined(MPQFILE_AIO)
    // We have to keep track of aiocb offsets manually, since the OS may change the value in the aiocbs under us
    off_t iocb_offsets[2] = {file_archive_offset + sector_table[which.location], file_archive_offset + sector_table[which.location] + (full_sector_size << 1)};
    
    // io_buffers
    void *io_buffers[2] = {read_buffer + full_sector_size, read_buffer + (full_sector_size << 2)};
#endif
    
#if defined(MPQFILE_PREAD_CHECK)
    // memcmp and decompression buffer
    void *memcmp_buffer = malloc(full_sector_size << 1);
#endif
    
#if defined(MPQFILE_AIO)
    // Prepare 2 aio control buffers
    struct aiocb iocb_buffer[2];
    struct aiocb *iocbs[2] = {iocb_buffer, iocb_buffer + 1};
    
    do {
        bzero(iocbs[0], sizeof(struct aiocb));
        bzero(iocbs[1], sizeof(struct aiocb));
        
        iocbs[0]->aio_fildes = archive_fd;
        iocbs[0]->aio_buf = io_buffers[0];
        iocbs[0]->aio_offset = iocb_offsets[0];
        iocbs[0]->aio_nbytes = full_sector_size << 1;
        iocbs[0]->aio_lio_opcode = LIO_READ;
        
        iocbs[1]->aio_fildes = archive_fd;
        iocbs[1]->aio_buf = io_buffers[1];
        iocbs[1]->aio_offset = iocb_offsets[1];
        iocbs[1]->aio_nbytes = full_sector_size << 1;
        iocbs[1]->aio_lio_opcode = LIO_READ;
        
        // Send the aio control buffers to the kernel
        perr = aio_read(iocbs[0]);
        perr = aio_read(iocbs[1]);
        if (perr == -1 && errno != EAGAIN) {
            if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            goto ErrorExit;
        }
    } while (perr == -1 && errno == EAGAIN);
#endif
    
    // This will keep track of which aiocb we're going to read from (and suspend on) next
    uint8_t current_iocb = 0;
    
    // Keep track of left-overs
    size_t bytes_available[2] = {0, 0};
    
    // Explicit cast is OK here, there cannot be more sectors than the 32-bit integer range
    uint32_t current_sector = (uint32_t)which.location;
    uint32_t last_needed_sector_plus_one = (uint32_t)(which.location + which.length);
    while (current_sector < last_needed_sector_plus_one) {
#if defined(MPQFILE_AIO)
        // Suspend until current_iocb is done
        aio_suspend((const struct aiocb **)(iocbs + current_iocb), 1, NULL);
        
        // Get result from iocbs[current_iocb]
        perr = aio_error(iocbs[current_iocb]);
        stage = 1;
        if (perr == EINPROGRESS) continue;
        if (perr) {
            if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:perr userInfo:nil];
            goto ErrorExit;
        }
        
        // This completes the aio command
        bytes_read = aio_return(iocbs[current_iocb]);
        
        uint8_t next_iocb = 1;
        if (current_iocb == 1) next_iocb = 0;
        
        // Compute sector_buffer and how many bytes are available in it (left-overs + new bytes)
        void *sector_buffer = io_buffers[current_iocb] - bytes_available[next_iocb];
        uint32_t sector_buffer_offset = 0;
        bytes_available[current_iocb] = bytes_read + bytes_available[next_iocb];
#else
        bytes_read = pread(archive_fd, read_buffer, read_size, file_archive_offset + sector_table[current_sector]);
        if (bytes_read == -1) {
            perr = -1;
            if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            goto ErrorExit;
        } else if (bytes_read == 0) {
            if (error) *error = [MPQError errorWithDomain:MPQErrorDomain code:errEndOfFile userInfo:nil];
            goto ErrorExit;
        }
        
        void *sector_buffer = read_buffer;
        uint32_t sector_buffer_offset = 0;
        bytes_available[current_iocb] = bytes_read;
#endif
        
        // Compute sector_size for the first iteration
        uint32_t sector_size = sector_table[current_sector + 1] - sector_table[current_sector];
        
        // Process as many sectors as possible with the current aio buffer
        stage = 2;
        while (bytes_available[current_iocb] >= sector_size) {
#if defined(MPQFILE_PREAD_CHECK)
            NSLog(@"Doing pread check...");
            perr = pread(archive_fd, memcmp_buffer, sector_size, file_archive_offset + sector_table[current_sector]);
            if (perr == -1) {
                if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
                goto ErrorExit;
            }
            
            perr = memcmp(memcmp_buffer, sector_buffer + sector_buffer_offset, sector_size);
            if (perr) {
                NSLog(@"memcmp failed!");
                perr = 0;
                if (error) *error = [MPQError errorWithDomain:MPQErrorDomain code:0xBABE userInfo:nil];
                goto ErrorExit;
            }
            
            sector_buffer = memcmp_buffer;
            sector_buffer_offset = 0;
#endif
            // If we have sector adlers and live sector checksum validation is on, checksum the sector and verify
            if (_checkSectorAdlers && (block_entry.flags & MPQFileHasSectorAdlers)) {
                // Explicit cast is OK here, adler32 is 32-bit
                uint32_t adler = (uint32_t)adler32(0L, Z_NULL, 0);
                adler = (uint32_t)adler32(adler, BUFFER_OFFSET(sector_buffer, sector_buffer_offset), sector_size);
                if (adler != _sector_adlers[current_sector]) {
                    if (error) {
                        NSDictionary *userInfo = [[NSDictionary alloc] initWithObjectsAndKeys:
                            [self fileInfo], MPQErrorFileInfo, 
                            [NSNumber numberWithUnsignedInt:current_sector], MPQErrorSectorIndex, 
                            [NSNumber numberWithUnsignedInt:adler], MPQErrorComputedSectorChecksum, 
                            [NSNumber numberWithUnsignedInt:_sector_adlers[current_sector]], MPQErrorExpectedSectorChecksum, 
                            nil];
                        *error = [MPQError errorWithDomain:MPQErrorDomain code:errInvalidSectorChecksum userInfo:userInfo];
                        [userInfo release];
                    }
                    goto ErrorExit;
                }
            }
            
            // If the file is encrypted, decrypt the sector
            if (encrypted) mpq_decrypt(BUFFER_OFFSET(sector_buffer, sector_buffer_offset), sector_size, encryption_key + current_sector, NO);
            
            // Destination buffer for the decompression function
            void *decompression_destination_buffer = BUFFER_OFFSET(buf, data_offset);
            
            // Figure out how big the sector should be when decompressed
            if (current_sector == last_sector) {
                decompressed_sector_size = block_entry.size - (last_sector * full_sector_size);
                decompression_destination_buffer = data_buffer;
            }
            
            // Use the proper decompression method
            if (block_entry.flags & MPQFileCompressed) {
                perr = SCompDecompress(decompression_destination_buffer, &decompressed_sector_size, BUFFER_OFFSET(sector_buffer, sector_buffer_offset), sector_size);
                if (perr == 0) {
                    if (error) *error = [MPQError errorWithDomain:MPQErrorDomain code:errDecompressionFailed userInfo:nil];
                    goto ErrorExit;
                }
            } else if ((block_entry.flags & MPQFileDiabloCompressed) && (sector_size < decompressed_sector_size)) {
                Decompress_pklib(decompression_destination_buffer, &decompressed_sector_size, BUFFER_OFFSET(sector_buffer, sector_buffer_offset), sector_size);
            } else {
                decompressed_sector_size = sector_size;
                memcpy(decompression_destination_buffer, BUFFER_OFFSET(sector_buffer, sector_buffer_offset), sector_size);
            }
            
            // Need to handle the first and last sector a bit differently
            if (current_sector == which.location) {
                assert(data_offset == 0);
                // Explicit cast is OK here, sector sizes are 32-bit
                uint32_t read_size = (uint32_t)bytesToKeep.location % full_sector_size;
                if (current_sector != last_sector) {
                    memmove(buf, BUFFER_OFFSET(buf, read_size), decompressed_sector_size - read_size);
                    data_offset += decompressed_sector_size - read_size;
                } else {
                    size_t bytes_to_copy = MIN(bytes_left, decompressed_sector_size - read_size);
                    memcpy(buf, BUFFER_OFFSET(decompression_destination_buffer, read_size), bytes_to_copy);
                    data_offset += bytes_to_copy;
                }
            } else if (current_sector == last_sector) {
                memcpy(BUFFER_OFFSET(buf, data_offset), decompression_destination_buffer, bytes_left);
                data_offset += bytes_left;
            } else data_offset += decompressed_sector_size;
            
            // Update bytes_left
            bytes_left = (data_offset > bytesToKeep.length) ? 0 : bytesToKeep.length - data_offset;
            
            // Move on the the next sector
            current_sector++;
            if (current_sector == last_needed_sector_plus_one) break;
            
            // Update the number of bytes available from the current aio buffer and update sector_size for the next sector
            bytes_available[current_iocb] -= sector_size;
            sector_buffer_offset += sector_size;
            sector_size = sector_table[current_sector + 1] - sector_table[current_sector];
        }
        
        // Immediatly exit if we're done
        if (current_sector == last_needed_sector_plus_one) break;

#if defined(MPQFILE_AIO)        
        // Copy left-overs in the appropriate left-over buffer
        memcpy(io_buffers[next_iocb] - bytes_available[current_iocb], sector_buffer + sector_buffer_offset, bytes_available[current_iocb]);

        // Prepare the next read
        iocb_offsets[current_iocb] = iocb_offsets[next_iocb] + (full_sector_size << 1);
        
        bzero(iocbs[current_iocb], sizeof(struct aiocb));
        iocbs[current_iocb]->aio_fildes = archive_fd;
        iocbs[current_iocb]->aio_buf = io_buffers[current_iocb];
        iocbs[current_iocb]->aio_nbytes = full_sector_size << 1;
        iocbs[current_iocb]->aio_offset = iocb_offsets[current_iocb];
        
        perr = aio_read(iocbs[current_iocb]);
        stage = 3;
        if (perr) {
            if (error) *error = [MPQError errorWithDomain:NSPOSIXErrorDomain code:perr userInfo:nil];
            goto ErrorExit;
        }
        
        // Update current_iocb
        current_iocb = next_iocb;
#endif
    }
    
#if defined(MPQFILE_AIO)
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
    
#if defined(MPQFILE_PREAD_CHECK)
    free(memcmp_buffer);
#endif
    
    // Make sure we respected our contract
    NSAssert(bytes_left == 0, @"Processed every sector but still missing data!");
    NSAssert(data_offset == bytesToKeep.length, @"data_offset is larger than bytesToKeep.length!");
    ReturnValueWithNoError(data_offset, error)
        
ErrorExit:
    MPQDebugLog(@"error %d occured at stage %d in readSectors", error, stage);
    if (perr == -1) MPQDebugLog(@"errno is %d", errno);
    
#if defined(MPQFILE_AIO)
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

#if defined(MPQFILE_PREAD_CHECK)
    free(memcmp_buffer);
#endif
    
    return -1;
}

- (ssize_t)read:(void *)buf size:(size_t)size error:(NSError **)error {
    if (file_pointer >= block_entry.size) ReturnValueWithNoError(0, error)
    
    size = MIN(size, block_entry.size - file_pointer);
    if (size == 0) ReturnValueWithNoError(0, error)
    
    uint32_t location = file_pointer / full_sector_size;
    NSRange sectors_range = NSMakeRange(location, ((file_pointer + size + full_sector_size - 1) / full_sector_size) - location);
    NSRange data_range = NSMakeRange(file_pointer, size);
        
    ssize_t bytes_read = [self _readSectors:buf range:sectors_range keeping:data_range error:error];
    // Explicit cast is OK here, MPQ file sizes are 32-bit
    if (bytes_read != -1) file_pointer += (uint32_t)bytes_read;
    return bytes_read;
}

- (NSData *)_copyRawSector:(uint32_t)index error:(NSError **)error {
    if (index > sector_table_length - 2) ReturnValueWithError(nil, MPQErrorDomain, errOutOfBounds, nil, error)
    size_t sector_size = sector_table[index + 1] - sector_table[index];
    ssize_t bytes_read = pread(archive_fd, read_buffer, sector_size, file_archive_offset + sector_table[index]);
    if (bytes_read == -1) ReturnValueWithPOSIXError(nil, nil, error)
    if ((size_t)bytes_read < sector_size) ReturnValueWithError(nil, MPQErrorDomain, errIO, nil, error)
    ReturnValueWithNoError([[NSData alloc] initWithBytes:read_buffer length:sector_size], error)
}

@end

#pragma mark -

@interface MPQFileConcreteMPQOneSector : MPQFile {
    int archive_fd;
    off_t file_archive_offset;
    uint32_t encryption_key;
    
    void *data_cache_;
}
@end

@implementation MPQFileConcreteMPQOneSector

- (id)initForFile:(NSDictionary *)descriptor error:(NSError **)error {
    self = [super initForFile:descriptor error:error];
    if (!self) return nil;
    
    archive_fd = [[descriptor objectForKey:@"FileDescriptor"] intValue];
    NSAssert(archive_fd, @"Invalid archive file descriptor");
    
    file_archive_offset = [[descriptor objectForKey:@"FileArchiveOffset"] longLongValue];
    encryption_key = [[descriptor objectForKey:@"EncryptionKey"] unsignedIntValue];
    
    ReturnValueWithNoError(self, error)
}

- (void)dealloc {
    if (data_cache_) free(data_cache_);
    [super dealloc];
}

- (ssize_t)read:(void *)buf size:(size_t)size error:(NSError **)error {
    if (file_pointer >= block_entry.size) ReturnValueWithNoError(0, error)
    
    size = MIN(size, block_entry.size - file_pointer);
    if (size == 0) ReturnValueWithNoError(0, error)

    // If we haven't decompressed the file already, do it now
    // TODO: stream decompression
    if (!data_cache_) {
        data_cache_ = malloc(block_entry.size);
        if (!data_cache_) ReturnValueWithError(-1, MPQErrorDomain, errOutOfMemory, nil, error)
        
        void *read_buffer = malloc(block_entry.archived_size);
        if (!read_buffer) ReturnValueWithError(-1, MPQErrorDomain, errOutOfMemory, nil, error)
                    
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
        if (block_entry.flags & MPQFileEncrypted) mpq_decrypt(read_buffer, block_entry.archived_size, encryption_key, NO);
        
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
    
    ReturnValueWithNoError(size, error)
}

- (NSData *)_copyRawSector:(uint32_t)index error:(NSError **)error {
    if (index > 0) ReturnValueWithError(nil, MPQErrorDomain, errOutOfBounds, nil, error)
    void *read_buffer = malloc(block_entry.archived_size);
    if (!read_buffer) ReturnValueWithError(nil, MPQErrorDomain, errOutOfMemory, nil, error)
    ssize_t bytes_read = pread(archive_fd, read_buffer, block_entry.archived_size, file_archive_offset);
    if (bytes_read == -1) {
        free(read_buffer);
        ReturnValueWithPOSIXError(nil, nil, error)
    }
    if ((uint32_t)bytes_read < block_entry.archived_size) {
        free(read_buffer);
        ReturnValueWithError(nil, MPQErrorDomain, errIO, nil, error)
    }
    ReturnValueWithNoError([[NSData alloc] initWithBytesNoCopy:read_buffer length:block_entry.archived_size freeWhenDone:YES], error)
}

@end
