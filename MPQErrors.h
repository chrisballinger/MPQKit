//
//  MPQErrors.h
//  MPQKit
//
//  Created by Jean-François Roy on 30/12/2006.
//  Copyright 2006 MacStorm. All rights reserved.
//

#import <stdint.h>

#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSError.h>
#import <Foundation/NSString.h>

// Error domains
extern NSString *const MPQErrorDomain;

// Error user info dictionary keys
extern NSString *const MPQErrorFileInfo;
extern NSString *const MPQErrorSectorIndex;
extern NSString *const MPQErrorComputedSectorChecksum;
extern NSString *const MPQErrorExpectedSectorChecksum;

// MPQ errors
enum {
    errUnknown = 1,
	errBlockTableFull = 2,
    errHashTableFull = 3,
    errHashTableEntryNotFound = 4,
    errCouldNotMemoryMapFile = 5,
    errFilenameTooLong = 6,
    errCouldNotConvertFilenameToASCII = 7,
    errOutOfMemory = 8,
    errFileIsOpen = 9,
    errFileExists = 10,
    errDelegateCancelled = 11,
    errOperationNotSupported = 12,
    errFileIsDeleted = 13,
    errFileIsInvalid = 14,
    errInconsistentCompressionFlags = 15,
    errInvalidCompressor = 16,
    errCannotResizeArchive = 17,
    errArchiveSizeOverflow = 18,
    errReadOnlyArchive = 19,
    errCouldNotConvertPathToFSRef = 20,
    errReadOnlyDestination = 21,
    errInvalidArchive = 22,
    errInvalidSectorTableCache = 23,
    errFilenameRequired = 24,
    errNoSignature = 25,
    errNoArchiveFile = 26,
    errInvalidArchiveVersion = 27,
    errInvalidArchiveOffset = 28,
    errInvalidClass = 29,
    errInvalidDisplacementMode = 30,
    errInvalidOffset = 31,
    errDecompressionFailed = 32,
    errEndOfFile = 33,
    errIO = 34,
    errInvalidAttributesFile = 35,
    errInvalidOperation = 36,
    errDataTooLarge = 37,
    errCouldNotConvertPathToURL = 38,
    errCouldNotConvertURLToFSRef = 39,
    errCouldNotConvertFSRefToURL = 40,
    errOutOfBounds = 41,
    errInvalidSectorChecksumData = 42,
    errInvalidSectorChecksum = 43,
};

static inline void MPQTransferErrorAndDrainPool(NSError **error, NSAutoreleasePool *p) {
    NSError *e = (error) ? *error : nil;
    [e retain];
    [p drain];
    [e autorelease];
}

@interface MPQError : NSError
@end
