#import <Foundation/Foundation.h>
#import <MPQKit/MPQKit.h>

#import "NSDataCryptoAdditions.h"

CFStringEncoding CFStringFileSystemEncoding(void);

int main(int argc, char *argv[]) {
    NSAutoreleasePool *p = [NSAutoreleasePool new];
    int i = 1;
    for (; i < argc; i++) {
        if (i > 1) printf("\n");
        
        NSString *archivePath = [NSString stringWithCString:argv[i] encoding:CFStringConvertEncodingToNSStringEncoding(CFStringFileSystemEncoding())];
        MPQArchive *archive = [[MPQArchive alloc] initWithPath:archivePath];
        if (!archive) {
            printf("INVALID ARCHIVE\n");
            break;
        }
        
        printf("-- archive information --\n\n");
        printf("%s\n\n", [[[archive archiveInfo] description] UTF8String]);
        
        // signatures
        BOOL isSigned;
        NSError *error = nil;
        BOOL valid = [archive verifyBlizzardWeakSignature:&isSigned error:&error];
        if (valid) printf("Blizzard weak signature: VALID\n");
        else if (isSigned && !error) printf("Blizzard weak signature: INVALID\n");
        else if (isSigned && [error code] != errNoSignature) printf("Blizzard weak signature: ERROR: %s\n", [[error description] UTF8String]);
        else printf("No weak signature\n");
        
        isSigned = [archive hasStrongSignature];
        if (isSigned) {
            valid = [archive verifyBlizzardStrongSignature:&error];
            if (valid) printf("Blizzard strong signature: VALID\n");
            else if (!error) printf("Blizzard strong signature: INVALID\n");
            else printf("Blizzard strong signature: ERROR: %s\n", [[error description] UTF8String]);
            
            valid = [archive verifyWoWSurveySignature:&error];
            if (valid) printf("WoW survey signature: VALID\n");
            else if (!error) printf("WoW survey signature: INVALID\n");
            else printf("Blizzard strong signature: ERROR: %s\n", [[error description] UTF8String]);
            
            valid = [archive verifyWoWMacPatchSignature:&error];
            if (valid) printf("WoW Macintosh patch signature: VALID\n");
            else if (!error) printf("WoW Macintosh patch signature: INVALID\n");
            else printf("Blizzard strong signature: ERROR: %s\n", [[error description] UTF8String]);
            
            valid = [archive verifyWarcraft3MapSignature:&error];
            if (valid) printf("Warcraft 3 map signature: VALID\n");
            else if (!error) printf("Warcraft 3 map signature: INVALID\n");
            else printf("Blizzard strong signature: ERROR: %s\n", [[error description] UTF8String]);
        } else {
            printf("No strong signature\n");
        }
        
        // files
        printf("\n\n-- file information --\n");
        [archive loadInternalListfile:nil];
        
        NSEnumerator *fileEnum = [archive fileInfoEnumerator];
        NSDictionary *fileInfo;
        while ((fileInfo = [fileEnum nextObject])) {
            uint32_t hash_position = [[fileInfo objectForKey:MPQFileHashPosition] unsignedIntValue];
            const char *utf8_filename = [[fileInfo objectForKey:MPQFilename] UTF8String];
            BOOL can_open = [[fileInfo objectForKey:MPQFileCanOpenWithoutFilename] boolValue];
            
            printf("\n%08x \"%s\"\n", hash_position, utf8_filename);
            
            if (!can_open) {
                printf("    **** cannot open this file ****\n");
                continue;
            }
            
            NSData *fileData = (!can_open) ? nil : [archive copyDataForFile:[fileInfo objectForKey:MPQFilename] locale:[[fileInfo objectForKey:MPQFileLocale] intValue]];
            if (!fileData && can_open) {
                printf("    **** could not read file's data ****\n");
                continue;
            }
            
            // general info
            printf("    file info: {\n");
            NSEnumerator *keys = [fileInfo keyEnumerator];
            id key;
            while ((key = [keys nextObject])) {
                const char *valueString;
                id value = [fileInfo objectForKey:key];
                
                if ([key isEqualToString:MPQFileFlags]) {
                    uint32_t flags = [value unsignedIntValue];
                    NSMutableArray *stringFlags = [[NSMutableArray alloc] init];
                    
                    // Known flags
                    if (flags & MPQFileValid) [stringFlags addObject:@"MPQFileValid"];
                    if (flags & MPQFileHasMetadata) [stringFlags addObject:@"MPQFileHasMetadata"];
                    if (flags & MPQFileDummy) [stringFlags addObject:@"MPQFileDummy"];
                    if (flags & MPQFileOneSector) [stringFlags addObject:@"MPQFileOneSector"];
                    if (flags & MPQFileOffsetAdjustedKey) [stringFlags addObject:@"MPQFileOffsetAdjustedKey"];
                    if (flags & MPQFileEncrypted) [stringFlags addObject:@"MPQFileEncrypted"];
                    if (flags & MPQFileCompressed) [stringFlags addObject:@"MPQFileCompressed"];
                    if (flags & MPQFileDiabloCompressed) [stringFlags addObject:@"MPQFileDiabloCompressed"];
                    
                    // Mask out known flags to reveal unknown flags
                    uint32_t unknownFlags = flags & (~MPQFileFlagsMask);
                    
                    if (unknownFlags > 0) value = [NSString stringWithFormat:@"0x%.8x: %@, UNKNOWN FLAGS: 0x%.8x", flags, [stringFlags componentsJoinedByString:@" | "], unknownFlags];
                    else value = [NSString stringWithFormat:@"0x%8x: %@", flags, [stringFlags componentsJoinedByString:@" | "]];
                    
                    valueString = [[value description] UTF8String];
                    [stringFlags release];
                }
                else if ([value isKindOfClass:[NSNumber class]]) valueString = [[NSString stringWithFormat:@"0x%.16qx", [value unsignedLongLongValue]] UTF8String];
                else valueString = [[value description] UTF8String];
                
                printf("        %s: %s\n", [[key description] UTF8String], valueString);
            }
            printf("    }\n");
            
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
    }
    
    [p release];
    return 0;
}
