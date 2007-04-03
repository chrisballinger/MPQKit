//
//  MPQErrors.h
//  MPQKit
//
//  Created by Jean-François Roy on 30/12/2006.
//  Copyright 2006 MacStorm. All rights reserved.
//

#import <Foundation/NSString.h>


// error domains
extern NSString *const MPQErrorDomain;

// MPQ errors
typedef enum {
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
} MPQError;