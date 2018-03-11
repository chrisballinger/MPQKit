/*
 *	MPQErrors.c
 *	MPQKit
 *
 *	Created by Jean-François Roy on 30/12/2006.
 *	Copyright 2006 MacStorm. All rights reserved.
 *
 */

#import <stdlib.h>
#import <string.h>
#import <Foundation/NSDictionary.h>
#import <MPQKit/MPQKitPrivate.h>

NSString* const MPQErrorDomain = @"MPQErrorDomain";

NSString* const MPQErrorFileInfo = @"MPQErrorFileInfo";
NSString* const MPQErrorSectorIndex = @"MPQErrorSectorIndex";
NSString* const MPQErrorComputedSectorChecksum = @"MPQErrorComputedSectorChecksum";
NSString* const MPQErrorExpectedSectorChecksum = @"MPQErrorExpectedSectorChecksum";

@implementation MPQError

- (NSString*)localizedDescription {
	NSDictionary* ui = [self userInfo];
	if (ui) {
		NSString* description = [ui objectForKey:NSLocalizedDescriptionKey];
		if (description)
			return description;
	}
	
	MPQNSInteger code = [self code];
	if ([[self domain] isEqualToString:MPQErrorDomain]) {
		switch (code) {
			case errUnknown: return [NSString stringWithFormat:@"%s (%ld)", "unknown error", (long)code];
			case errBlockTableFull: return [NSString stringWithFormat:@"%s (%ld)", "block table is full", (long)code];
			case errHashTableFull: return [NSString stringWithFormat:@"%s (%ld)", "hash table is full", (long)code];
			case errHashTableEntryNotFound: return [NSString stringWithFormat:@"%s (%ld)", "hash table entry not found", (long)code];
			case errCouldNotMemoryMapFile: return [NSString stringWithFormat:@"%s (%ld)", "could not mmap file", (long)code];
			case errFilenameTooLong: return [NSString stringWithFormat:@"%s (%ld)", "filename too long", (long)code];
			case errCouldNotConvertFilenameToASCII: return [NSString stringWithFormat:@"%s (%ld)", "could not convert filename to ASCII", (long)code];
			case errOutOfMemory: return [NSString stringWithFormat:@"%s (%ld)", "out of memory", (long)code];
			case errFileIsOpen: return [NSString stringWithFormat:@"%s (%ld)", "file is open", (long)code];
			case errFileExists: return [NSString stringWithFormat:@"%s (%ld)", "file exists", (long)code];
			case errDelegateCancelled: return [NSString stringWithFormat:@"%s (%ld)", "delegate cancelled", (long)code];
			case errOperationNotSupported: return [NSString stringWithFormat:@"%s (%ld)", "operation not supported", (long)code];
			case errFileIsDeleted: return [NSString stringWithFormat:@"%s (%ld)", "file is deleted", (long)code];
			case errFileIsInvalid: return [NSString stringWithFormat:@"%s (%ld)", "file is invalid", (long)code];
			case errInconsistentCompressionFlags: return [NSString stringWithFormat:@"%s (%ld)", "inconsistent compression flags", (long)code];
			case errInvalidCompressor: return [NSString stringWithFormat:@"%s (%ld)", "invalid compressor", (long)code];
			case errCannotResizeArchive: return [NSString stringWithFormat:@"%s (%ld)", "cannot resize archive", (long)code];
			case errArchiveSizeOverflow: return [NSString stringWithFormat:@"%s (%ld)", "archive size overflow", (long)code];
			case errReadOnlyArchive: return [NSString stringWithFormat:@"%s (%ld)", "read-only archive", (long)code];
			case errCouldNotConvertPathToFSRef: return [NSString stringWithFormat:@"%s (%ld)", "could not convert path to FSRef", (long)code];
			case errReadOnlyDestination: return [NSString stringWithFormat:@"%s (%ld)", "read-only destination", (long)code];
			case errInvalidArchive: return [NSString stringWithFormat:@"%s (%ld)", "invalid archive", (long)code];
			case errInvalidSectorTableCache: return [NSString stringWithFormat:@"%s (%ld)", "invalid sector table cache", (long)code];
			case errFilenameRequired: return [NSString stringWithFormat:@"%s (%ld)", "filename required", (long)code];
			case errNoSignature: return [NSString stringWithFormat:@"%s (%ld)", "no signature", (long)code];
			case errNoArchiveFile: return [NSString stringWithFormat:@"%s (%ld)", "no archive file", (long)code];
			case errInvalidArchiveVersion: return [NSString stringWithFormat:@"%s (%ld)", "invalid archive version", (long)code];
			case errInvalidArchiveOffset: return [NSString stringWithFormat:@"%s (%ld)", "invalid archive offset", (long)code];
			case errInvalidClass: return [NSString stringWithFormat:@"%s (%ld)", "invalid class", (long)code];
			case errInvalidDisplacementMode: return [NSString stringWithFormat:@"%s (%ld)", "invalid displacement mode", (long)code];
			case errInvalidOffset: return [NSString stringWithFormat:@"%s (%ld)", "invalid offset", (long)code];
			case errDecompressionFailed: return [NSString stringWithFormat:@"%s (%ld)", "decompression failed", (long)code];
			case errEndOfFile: return [NSString stringWithFormat:@"%s (%ld)", "errEndOfFile", (long)code];
			case errIO: return [NSString stringWithFormat:@"%s (%ld)", "IO error", (long)code];
			case errInvalidAttributesFile: return [NSString stringWithFormat:@"%s (%ld)", "invalid attributes file", (long)code];
			case errInvalidOperation: return [NSString stringWithFormat:@"%s (%ld)", "invalid operation", (long)code];
			case errDataTooLarge: return [NSString stringWithFormat:@"%s (%ld)", "data too large", (long)code];
			case errCouldNotConvertPathToURL: return [NSString stringWithFormat:@"%s (%ld)", "could not convert path to URL", (long)code];
			case errCouldNotConvertURLToFSRef: return [NSString stringWithFormat:@"%s (%ld)", "could not convert URL to FSRef", (long)code];
			case errCouldNotConvertFSRefToURL: return [NSString stringWithFormat:@"%s (%ld)", "could not convert FSRef to URL", (long)code];
			case errOutOfBounds: return [NSString stringWithFormat:@"%s (%ld)", "out of bounds", (long)code];
			case errInvalidSectorChecksumData: return [NSString stringWithFormat:@"%s (%ld)", "invalid sector checksum data", (long)code];
			case errInvalidSectorChecksum: return [NSString stringWithFormat:@"%s (%ld)", "invalid sector checksum", (long)code];
			case errInvalidSignature: return [NSString stringWithFormat:@"%s (%ld)", "invalid signature", (long)code];
			default: abort();
		}
	} else if ([[self domain] isEqualToString:NSPOSIXErrorDomain]) {
		return [NSString stringWithFormat:@"%s (%ld)", strerror((int)code), (long)code];
	}
	
	return [super localizedDescription];
}

@end
