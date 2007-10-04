//
//  mpqdump.m
//  MPQKit
//
//  Created by Jean-François Roy on 01/01/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MPQKit/MPQKit.h>
#import <MPQKit/MPQFilePrivate.h>

#import <getopt.h>

#import "NSDataCryptoAdditions.h"

CFStringEncoding CFStringFileSystemEncoding(void);

static const char *optString = "cs";
static const struct option longOpts[] = {
    { "compute-checksums", no_argument, NULL, 'c' },
    { "sector-analysis", no_argument, NULL, 's' },
    { "listfile", required_argument, NULL, 0 },
    { NULL, no_argument, NULL, 0 }
};

static void analyse_sectors(MPQFile *file, NSDictionary *fileInfo, uint32_t flags, uint32_t full_sector_size) {
    NSError *error;
    
    printf("\n");
    
    uint32_t file_size = [[fileInfo objectForKey:MPQFileSize] unsignedIntValue];
    uint32_t sector_count = [[fileInfo objectForKey:MPQFileNumberOfSectors] unsignedIntValue];
    uint32_t encryption_key = [[fileInfo objectForKey:MPQFileEncryptionKey] unsignedIntValue];
    
    if (sector_count == 0) printf("    **** file has 0 sectors ****\n");
    else if (!(flags & MPQFileCompressed)) printf("    **** file is not compressed or was compressed with Diablo compression ****\n");
    else {
        NSData *raw_sector_data = [file _copyRawSector:0 error:&error];        
        if (!raw_sector_data) {
            printf("    **** could not get raw sector 0 data ****\n");
            printf("    %s\n", [[error description] UTF8String]);
        } else if ((sector_count == 1 && [raw_sector_data length] == file_size) || [raw_sector_data length] == full_sector_size) {
            printf("    **** sector 0 is uncompressed ****\n");
            [raw_sector_data release];
        } else {
            if ((flags & MPQFileEncrypted)) {
                NSMutableData *mutable_sector_data = [raw_sector_data mutableCopy];
                mpq_decrypt([mutable_sector_data mutableBytes], [mutable_sector_data length], encryption_key, NO);
                [raw_sector_data release];
                raw_sector_data = mutable_sector_data;
            }
            
            const uint8_t *raw_sector = [raw_sector_data bytes];
            NSMutableArray *stringCompressors = [[NSMutableArray alloc] init];
            if ((*raw_sector & MPQPKWARECompression)) [stringCompressors addObject:@"MPQPKWARECompression"];
            if ((*raw_sector & MPQZLIBCompression)) [stringCompressors addObject:@"MPQZLIBCompression"];
            if ((*raw_sector & MPQBZIP2Compression)) [stringCompressors addObject:@"MPQBZIP2Compression"];
            if ((*raw_sector & MPQHuffmanTreeCompression)) [stringCompressors addObject:@"MPQHuffmanTreeCompression"];
            if ((*raw_sector & MPQMonoADPCMCompression)) [stringCompressors addObject:@"MPQMonoADPCMCompression"];
            if ((*raw_sector & MPQStereoADPCMCompression)) [stringCompressors addObject:@"MPQStereoADPCMCompression"];
            
            // Mask out known flags to reveal unknown flags
            uint32_t unknownCompressors = *raw_sector & (~MPQCompressorMask);
            
            NSString *value;
            if (unknownCompressors != 0)
                value = [NSString stringWithFormat:@"0x%02x: %@, UNKNOWN COMPRESSORS: 0x%02x", *raw_sector, [stringCompressors componentsJoinedByString:@" | "], unknownCompressors];
            else value = [NSString stringWithFormat:@"0x%02x: %@", *raw_sector, [stringCompressors componentsJoinedByString:@" | "]];
            
            printf("    sector 0 compressors: %s\n", [value UTF8String]);
            
            [stringCompressors release];
            [raw_sector_data release];
        }
        
        if (sector_count > 1) {
            raw_sector_data = [file _copyRawSector:1 error:&error];
            if (!raw_sector_data) {
                printf("    **** could not get raw sector 1 data ****\n");
                printf("    %s\n", [[error description] UTF8String]);
            } else if ((sector_count == 1 && [raw_sector_data length] == file_size) || [raw_sector_data length] == full_sector_size) {
                printf("    **** sector 1 is uncompressed ****\n");
                [raw_sector_data release];
            } else {
                if ((flags & MPQFileEncrypted)) {
                    NSMutableData *mutable_sector_data = [raw_sector_data mutableCopy];
                    mpq_decrypt([mutable_sector_data mutableBytes], [mutable_sector_data length], encryption_key + 1, NO);
                    [raw_sector_data release];
                    raw_sector_data = mutable_sector_data;
                }
                
                const uint8_t *raw_sector = [raw_sector_data bytes];
                NSMutableArray *stringCompressors = [[NSMutableArray alloc] init];
                if ((*raw_sector & MPQPKWARECompression)) [stringCompressors addObject:@"MPQPKWARECompression"];
                if ((*raw_sector & MPQZLIBCompression)) [stringCompressors addObject:@"MPQZLIBCompression"];
                if ((*raw_sector & MPQBZIP2Compression)) [stringCompressors addObject:@"MPQBZIP2Compression"];
                if ((*raw_sector & MPQHuffmanTreeCompression)) [stringCompressors addObject:@"MPQHuffmanTreeCompression"];
                if ((*raw_sector & MPQMonoADPCMCompression)) [stringCompressors addObject:@"MPQMonoADPCMCompression"];
                if ((*raw_sector & MPQStereoADPCMCompression)) [stringCompressors addObject:@"MPQStereoADPCMCompression"];
                
                // Mask out known flags to reveal unknown flags
                uint32_t unknownCompressors = *raw_sector & (~MPQCompressorMask);
                
                NSString *value;
                if (unknownCompressors != 0)
                    value = [NSString stringWithFormat:@"0x%02x: %@, UNKNOWN COMPRESSORS: 0x%02x", *raw_sector, [stringCompressors componentsJoinedByString:@" | "], unknownCompressors];
                else value = [NSString stringWithFormat:@"0x%02x: %@", *raw_sector, [stringCompressors componentsJoinedByString:@" | "]];
                
                printf("    sector 1 compressors: %s\n", [value UTF8String]);
                
                [stringCompressors release];
                [raw_sector_data release];
            }
        } else printf("    **** file only has 1 sector ****\n");
    }
}

static void checksum_analysis(MPQFile *file, NSDictionary *fileInfo) {
    NSError *error;
    
    printf("\n");
    
    // read entire file for checksums
    NSData *fileData = [file copyDataToEndOfFile:&error];
    if (!fileData) {
        printf("    **** could not read the file's data ****\n");
        printf("    %s\n", [[error description] UTF8String]);
        return;
    }
    
    // CRC
    uint32_t crc = 0;
    mpq_crc32([fileData bytes], [fileData length], &crc, MPQ_CRC_INIT | MPQ_CRC_UPDATE | MPQ_CRC_FINALIZE);
    NSNumber *storedCRC = [fileInfo objectForKey:@"CRC"];
    if (storedCRC) {
        if ([storedCRC unsignedIntValue] == crc) printf("    computed CRC: 0x%08x (VALID)\n", crc);
        else printf("    computed CRC: 0x%08x (INVALID)\n", crc);
    } else printf("    computed CRC: 0x%08x (CANNOT COMPARE)\n", crc);
    
    // MD5
    NSData *md5 = [fileData md5];
    NSData *storedMD5 = [fileInfo objectForKey:@"MD5Sum"];
    if (storedMD5) {
        if ([storedMD5 isEqualToData:md5]) printf("    computed MD5: %s (VALID)\n", [[md5 description] UTF8String]);
        else printf("    computed MD5: %s (INVALID)\n", [[md5 description] UTF8String]);
    } else printf("    computed MD5: %s (CANNOT COMPARE)\n", [[md5 description] UTF8String]);
    
    // done with this file's data
    [fileData release];
}

int main(int argc, char *argv[]) {
    NSAutoreleasePool *p = [NSAutoreleasePool new];
    NSError *error = nil;
    
    BOOL computeChecksums = NO;
    BOOL sectorAnalysis = NO;
    NSMutableArray *listfiles = [NSMutableArray arrayWithCapacity:0x10];
    
    // Parse options
    int longIndex;
    int opt = getopt_long(argc, argv, optString, longOpts, &longIndex);
    while (opt != -1) {
        switch (opt) {
            case 'c':
                computeChecksums = YES;
                break;
                
            case 's':
                sectorAnalysis = YES;
                break;
                
            case 0:
                if( strcmp( "listfile", longOpts[longIndex].name ) == 0 ) {
                    [listfiles addObject:[[NSString stringWithCString:optarg encoding:NSUTF8StringEncoding] stringByStandardizingPath]];
                }
                break;
        }
        
        opt = getopt_long(argc, argv, optString, longOpts, &longIndex);
    }
    
    int i = optind;
    for (; i < argc; i++) {
        if (i > optind) printf("\n");
        
        NSAutoreleasePool *ap = [NSAutoreleasePool new];
        
        NSString *archivePath = [NSString stringWithCString:argv[i] encoding:CFStringConvertEncodingToNSStringEncoding(CFStringFileSystemEncoding())];
        MPQArchive *archive = [[MPQArchive alloc] initWithPath:archivePath error:&error];
        if (!archive) {
            printf("INVALID ARCHIVE\n");
            printf("    %s\n", [[error description] UTF8String]);
            [ap release];
            continue;
        }
        
        if ([listfiles count] > 0) {
            NSEnumerator *listfileEnum = [listfiles objectEnumerator];
            NSString *listfile;
            while ((listfile = [listfileEnum nextObject])) [archive addContentsOfFileToFileList:listfile];
        }
        
        printf("-- archive information --\n\n");
        printf("%s\n\n", [[[archive archiveInfo] description] UTF8String]);
        
        uint32_t full_sector_size = 512 << [[[archive archiveInfo] objectForKey:MPQSectorSizeShift] unsignedIntValue];
        
        // signatures
        BOOL isSigned;
        BOOL valid = [archive verifyBlizzardWeakSignature:&isSigned error:&error];
        if (valid) printf("Blizzard weak signature: VALID\n");
        else if (isSigned && !error) printf("Blizzard weak signature: INVALID\n");
        else if (isSigned && [error code] != errNoSignature) printf("Blizzard weak signature: ERROR: %s\n", [[error description] UTF8String]);
        else printf("No weak signature\n");
        
        isSigned = [archive hasStrongSignature];
        if (isSigned) {
            valid = [archive verifyBlizzardStrongSignature:&error];
            if (valid) printf("Blizzard strong signature: VALID");
            else if (!error) printf("Blizzard strong signature: INVALID");
            else printf("Blizzard strong signature: ERROR: %s", [[error description] UTF8String]);
            printf("\n");
            
            valid = [archive verifyWoWSurveySignature:&error];
            if (valid) printf("WoW survey signature: VALID");
            else if (!error) printf("WoW survey signature: INVALID");
            else printf("WoW survey signature: ERROR: %s", [[error description] UTF8String]);
            printf("\n");
            
            valid = [archive verifyWoWMacPatchSignature:&error];
            if (valid) printf("WoW Macintosh patch signature: VALID");
            else if (!error) printf("WoW Macintosh patch signature: INVALID");
            else printf("WoW Macintosh patch signature: ERROR: %s", [[error description] UTF8String]);
            printf("\n");
            
            valid = [archive verifyWarcraft3MapSignature:&error];
            if (valid) printf("Warcraft 3 map signature: VALID");
            else if (!error) printf("Warcraft 3 map signature: INVALID");
            else printf("Warcraft 3 map signature: ERROR: %s", [[error description] UTF8String]);
            printf("\n");
            
            valid = [archive verifyStarcraftMapSignature:&error];
            if (valid) printf("Starcraft map signature: VALID");
            else if (!error) printf("Starcraft map signature: INVALID");
            else printf("Starcraft map signature: ERROR: %s", [[error description] UTF8String]);
            printf("\n");
        } else printf("No strong signature\n");
        
        // files
        printf("\n-- file information --\n");
        [archive loadInternalListfile:nil];
        
        NSEnumerator *fileEnum = [archive fileInfoEnumerator];
        NSDictionary *fileInfo;
        while ((fileInfo = [fileEnum nextObject])) {
            uint32_t hash_position = [[fileInfo objectForKey:MPQFileHashPosition] unsignedIntValue];
            const char *utf8_filename = [[fileInfo objectForKey:MPQFilename] UTF8String];
            BOOL can_open = [[fileInfo objectForKey:MPQFileCanOpenWithoutFilename] boolValue];
            
            // file hash position and filename
            printf("\n%08x \"%s\"\n", hash_position, utf8_filename);
            
            uint32_t flags = [[fileInfo objectForKey:MPQFileFlags] unsignedIntValue];
            
            // file info
            printf("    file info: {\n");
            NSEnumerator *keys = [fileInfo keyEnumerator];
            id key;
            while ((key = [keys nextObject])) {
                const char *valueString;
                id value = [fileInfo objectForKey:key];
                
                if ([key isEqualToString:MPQFileFlags]) {
                    NSMutableArray *stringFlags = [[NSMutableArray alloc] init];
                    
                    // Known flags
                    if (flags & MPQFileValid) [stringFlags addObject:@"MPQFileValid"];
                    if (flags & MPQFileHasSectorAdlers) [stringFlags addObject:@"MPQFileHasSectorAdlers"];
                    if (flags & MPQFileStopSearchMarker) [stringFlags addObject:@"MPQFileStopSearchMarker"];
                    if (flags & MPQFileOneSector) [stringFlags addObject:@"MPQFileOneSector"];
                    if (flags & MPQFileOffsetAdjustedKey) [stringFlags addObject:@"MPQFileOffsetAdjustedKey"];
                    if (flags & MPQFileEncrypted) [stringFlags addObject:@"MPQFileEncrypted"];
                    if (flags & MPQFileCompressed) [stringFlags addObject:@"MPQFileCompressed"];
                    if (flags & MPQFileDiabloCompressed) [stringFlags addObject:@"MPQFileDiabloCompressed"];
                    
                    // Mask out known flags to reveal unknown flags
                    uint32_t unknownFlags = flags & (~MPQFileFlagsMask);
                    
                    if (unknownFlags != 0) value = [NSString stringWithFormat:@"0x%08x: %@, UNKNOWN FLAGS: 0x%08x", flags, [stringFlags componentsJoinedByString:@" | "], unknownFlags];
                    else value = [NSString stringWithFormat:@"0x%08x: %@", flags, [stringFlags componentsJoinedByString:@" | "]];
                    
                    valueString = [[value description] UTF8String];
                    [stringFlags release];
                }
                else if ([key isEqualToString:MPQFileLocale]) valueString = [[[MPQArchive localeForMPQLocale:[value unsignedShortValue]] localeIdentifier] UTF8String];
                else if ([key isEqualToString:MPQFileCanOpenWithoutFilename]) valueString = ([value boolValue]) ? "YES" : "NO";
                else if ([value isKindOfClass:[NSNumber class]]) valueString = [[NSString stringWithFormat:@"0x%016qx", [value unsignedLongLongValue]] UTF8String];
                else valueString = [[value description] UTF8String];
                
                printf("        %s: %s\n", [[key description] UTF8String], valueString);
            }
            printf("    }\n");
            
            // can open bail
            if (!can_open) {
                printf("\n    **** cannot open this file ****\n");
                continue;
            }
            
            // open file
            MPQFile *file = [archive openFileAtPosition:[[fileInfo objectForKey:MPQFileHashPosition] unsignedIntValue] error:&error];
            if (!file && can_open) {
                printf("\n    **** could not open the file ****\n");
                printf("    %s\n", [[error description] UTF8String]);
                continue;
            }
            
            if (sectorAnalysis) analyse_sectors(file, fileInfo, flags, full_sector_size);
            if (computeChecksums) checksum_analysis(file, fileInfo);
            
            // done with file
            [file release];
        }
        
        // We're done with this archive
        [archive release];
        [ap release];
    }
    
    [p release];
    return 0;
}
