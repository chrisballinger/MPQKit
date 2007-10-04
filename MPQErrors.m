/*
 *  MPQErrors.c
 *  MPQKit
 *
 *  Created by Jean-François Roy on 30/12/2006.
 *  Copyright 2006 MacStorm. All rights reserved.
 *
 */

#import <stdlib.h>
#import <string.h>
#import <Foundation/NSDictionary.h>
#import <MPQKit/MPQKitPrivate.h>

NSString *const MPQErrorDomain = @"MPQErrorDomain";

NSString *const MPQErrorFileInfo = @"MPQErrorFileInfo";
NSString *const MPQErrorSectorIndex = @"MPQErrorSectorIndex";
NSString *const MPQErrorComputedSectorChecksum = @"MPQErrorComputedSectorChecksum";
NSString *const MPQErrorExpectedSectorChecksum = @"MPQErrorExpectedSectorChecksum";

@implementation MPQError

- (NSString *)localizedDescription {
    NSDictionary *ui = [self userInfo];
    if (ui) {
        NSString *description = [ui objectForKey:NSLocalizedDescriptionKey];
        if (description) return description;
    }
    
    MPQNSInteger code = [self code];
    if ([[self domain] isEqualToString:MPQErrorDomain]) {
        switch (code) {
            case errUnknown: return [NSString stringWithFormat:@"%s (%d)", "errUnknown", code];
            case errBlockTableFull: return [NSString stringWithFormat:@"%s (%d)", "errBlockTableFull", code];
            case errHashTableFull: return [NSString stringWithFormat:@"%s (%d)", "errHashTableFull", code];
            case errHashTableEntryNotFound: return [NSString stringWithFormat:@"%s (%d)", "errHashTableEntryNotFound", code];
            case errCouldNotMemoryMapFile: return [NSString stringWithFormat:@"%s (%d)", "errCouldNotMemoryMapFile", code];
            case errFilenameTooLong: return [NSString stringWithFormat:@"%s (%d)", "errFilenameTooLong", code];
            case errCouldNotConvertFilenameToASCII: return [NSString stringWithFormat:@"%s (%d)", "errCouldNotConvertFilenameToASCII", code];
            case errOutOfMemory: return [NSString stringWithFormat:@"%s (%d)", "errOutOfMemory", code];
            case errFileIsOpen: return [NSString stringWithFormat:@"%s (%d)", "errFileIsOpen", code];
            case errFileExists: return [NSString stringWithFormat:@"%s (%d)", "errFileExists", code];
            case errDelegateCancelled: return [NSString stringWithFormat:@"%s (%d)", "errDelegateCancelled", code];
            case errOperationNotSupported: return [NSString stringWithFormat:@"%s (%d)", "errOperationNotSupported", code];
            case errFileIsDeleted: return [NSString stringWithFormat:@"%s (%d)", "errFileIsDeleted", code];
            case errFileIsInvalid: return [NSString stringWithFormat:@"%s (%d)", "errFileIsInvalid", code];
            case errInconsistentCompressionFlags: return [NSString stringWithFormat:@"%s (%d)", "errInconsistentCompressionFlags", code];
            case errInvalidCompressor: return [NSString stringWithFormat:@"%s (%d)", "errInvalidCompressor", code];
            case errCannotResizeArchive: return [NSString stringWithFormat:@"%s (%d)", "errCannotResizeArchive", code];
            case errArchiveSizeOverflow: return [NSString stringWithFormat:@"%s (%d)", "errArchiveSizeOverflow", code];
            case errReadOnlyArchive: return [NSString stringWithFormat:@"%s (%d)", "errReadOnlyArchive", code];
            case errCouldNotConvertPathToFSRef: return [NSString stringWithFormat:@"%s (%d)", "errCouldNotConvertPathToFSRef", code];
            case errReadOnlyDestination: return [NSString stringWithFormat:@"%s (%d)", "errReadOnlyDestination", code];
            case errInvalidArchive: return [NSString stringWithFormat:@"%s (%d)", "errInvalidArchive", code];
            case errInvalidSectorTableCache: return [NSString stringWithFormat:@"%s (%d)", "errInvalidSectorTableCache", code];
            case errFilenameRequired: return [NSString stringWithFormat:@"%s (%d)", "errFilenameRequired", code];
            case errNoSignature: return [NSString stringWithFormat:@"%s (%d)", "errNoSignature", code];
            case errNoArchiveFile: return [NSString stringWithFormat:@"%s (%d)", "errNoArchiveFile", code];
            case errInvalidArchiveVersion: return [NSString stringWithFormat:@"%s (%d)", "errInvalidArchiveVersion", code];
            case errInvalidArchiveOffset: return [NSString stringWithFormat:@"%s (%d)", "errInvalidArchiveOffset", code];
            case errInvalidClass: return [NSString stringWithFormat:@"%s (%d)", "errInvalidClass", code];
            case errInvalidDisplacementMode: return [NSString stringWithFormat:@"%s (%d)", "errInvalidDisplacementMode", code];
            case errInvalidOffset: return [NSString stringWithFormat:@"%s (%d)", "errInvalidOffset", code];
            case errDecompressionFailed: return [NSString stringWithFormat:@"%s (%d)", "errDecompressionFailed", code];
            case errEndOfFile: return [NSString stringWithFormat:@"%s (%d)", "errEndOfFile", code];
            case errIO: return [NSString stringWithFormat:@"%s (%d)", "errIO", code];
            case errInvalidAttributesFile: return [NSString stringWithFormat:@"%s (%d)", "errInvalidAttributesFile", code];
            case errInvalidOperation: return [NSString stringWithFormat:@"%s (%d)", "errInvalidOperation", code];
            case errDataTooLarge: return [NSString stringWithFormat:@"%s (%d)", "errDataTooLarge", code];
            case errCouldNotConvertPathToURL: return [NSString stringWithFormat:@"%s (%d)", "errCouldNotConvertPathToURL", code];
            case errCouldNotConvertURLToFSRef: return [NSString stringWithFormat:@"%s (%d)", "errCouldNotConvertURLToFSRef", code];
            case errCouldNotConvertFSRefToURL: return [NSString stringWithFormat:@"%s (%d)", "errCouldNotConvertFSRefToURL", code];
            case errOutOfBounds: return [NSString stringWithFormat:@"%s (%d)", "errOutOfBounds", code];
            case errInvalidSectorChecksumData: return [NSString stringWithFormat:@"%s (%d)", "errInvalidSectorChecksumData", code];
            case errInvalidSectorChecksum: return [NSString stringWithFormat:@"%s (%d)", "errInvalidSectorChecksum", code];
            default: abort();
        }
    } else if ([[self domain] isEqualToString:NSPOSIXErrorDomain]) {
        return [NSString stringWithFormat:@"%s (%d)", strerror((int)code), code];
    }
    
    return [super localizedDescription];
}

@end
