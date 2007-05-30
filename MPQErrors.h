//
//  MPQErrors.h
//  MPQKit
//
//  Created by Jean-François Roy on 30/12/2006.
//  Copyright 2006 MacStorm. All rights reserved.
//

#import <stdint.h>

#import <Foundation/NSString.h>
#import <Foundation/NSAutoreleasePool.h>


// error domains
extern NSString *const MPQErrorDomain;

// MPQ errors
enum {
    errUnknown = 1,
	errBlockTableFull,
    errHashTableFull,
    errHashTableEntryNotFound,
    errCouldNotMemoryMapFile,
    errFilenameTooLong,
    errCouldNotConvertFilenameToASCII,
    errOutOfMemory,
    errFileIsOpen,
    errFileExists,
    errDelegateCancelled,
    errOperationNotSupported,
    errCouldNotReadFile,
    errFileIsDeleted,
    errFileIsInvalid,
    errInconsistentCompressionFlags,
    errInvalidCompressor,
    errCannotResizeArchive,
    errArchiveSizeOverflow,
    errReadOnlyArchive,
    errCouldNotConvertPathToFSRef,
    errReadOnlyDestination,
    errInvalidArchive,
    errInvalidSectorTableCache,
    errFilenameRequired,
    errNoSignature,
    errNoArchiveFile,
    errInvalidArchiveVersion,
    errInvalidArchiveOffset,
    errInvalidClass,
    errInvalidDisplacementMode,
    errInvalidOffset,
    errDecompressionFailed,
    errEndOfFile,
    errInvalidAttributesFile,
    errInvalidOperation,
    errDataTooLarge,
};

typedef uint32_t MPQError;

inline void MPQTransferErrorAndDrainPool(NSError **error, NSAutoreleasePool *p);
