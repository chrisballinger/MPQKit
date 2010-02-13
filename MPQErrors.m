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
			case errUnknown: return [NSString stringWithFormat:@"%s (%d)", "unknown error", code];
			case errBlockTableFull: return [NSString stringWithFormat:@"%s (%d)", "block table is full", code];
			case errHashTableFull: return [NSString stringWithFormat:@"%s (%d)", "hash table is full", code];
			case errHashTableEntryNotFound: return [NSString stringWithFormat:@"%s (%d)", "hash table entry not found", code];
			case errCouldNotMemoryMapFile: return [NSString stringWithFormat:@"%s (%d)", "could not mmap file", code];
			case errFilenameTooLong: return [NSString stringWithFormat:@"%s (%d)", "filename too long", code];
			case errCouldNotConvertFilenameToASCII: return [NSString stringWithFormat:@"%s (%d)", "could not convert filename to ASCII", code];
			case errOutOfMemory: return [NSString stringWithFormat:@"%s (%d)", "out of memory", code];
			case errFileIsOpen: return [NSString stringWithFormat:@"%s (%d)", "file is open", code];
			case errFileExists: return [NSString stringWithFormat:@"%s (%d)", "file exists", code];
			case errDelegateCancelled: return [NSString stringWithFormat:@"%s (%d)", "delegate cancelled", code];
			case errOperationNotSupported: return [NSString stringWithFormat:@"%s (%d)", "operation not supported", code];
			case errFileIsDeleted: return [NSString stringWithFormat:@"%s (%d)", "file is deleted", code];
			case errFileIsInvalid: return [NSString stringWithFormat:@"%s (%d)", "file is invalid", code];
			case errInconsistentCompressionFlags: return [NSString stringWithFormat:@"%s (%d)", "inconsistent compression flags", code];
			case errInvalidCompressor: return [NSString stringWithFormat:@"%s (%d)", "invalid compressor", code];
			case errCannotResizeArchive: return [NSString stringWithFormat:@"%s (%d)", "cannot resize archive", code];
			case errArchiveSizeOverflow: return [NSString stringWithFormat:@"%s (%d)", "archive size overflow", code];
			case errReadOnlyArchive: return [NSString stringWithFormat:@"%s (%d)", "read-only archive", code];
			case errCouldNotConvertPathToFSRef: return [NSString stringWithFormat:@"%s (%d)", "could not convert path to FSRef", code];
			case errReadOnlyDestination: return [NSString stringWithFormat:@"%s (%d)", "read-only destination", code];
			case errInvalidArchive: return [NSString stringWithFormat:@"%s (%d)", "invalid archive", code];
			case errInvalidSectorTableCache: return [NSString stringWithFormat:@"%s (%d)", "invalid sector table cache", code];
			case errFilenameRequired: return [NSString stringWithFormat:@"%s (%d)", "filename required", code];
			case errNoSignature: return [NSString stringWithFormat:@"%s (%d)", "no signature", code];
			case errNoArchiveFile: return [NSString stringWithFormat:@"%s (%d)", "no archive file", code];
			case errInvalidArchiveVersion: return [NSString stringWithFormat:@"%s (%d)", "invalid archive version", code];
			case errInvalidArchiveOffset: return [NSString stringWithFormat:@"%s (%d)", "invalid archive offset", code];
			case errInvalidClass: return [NSString stringWithFormat:@"%s (%d)", "invalid class", code];
			case errInvalidDisplacementMode: return [NSString stringWithFormat:@"%s (%d)", "invalid displacement mode", code];
			case errInvalidOffset: return [NSString stringWithFormat:@"%s (%d)", "invalid offset", code];
			case errDecompressionFailed: return [NSString stringWithFormat:@"%s (%d)", "decompression failed", code];
			case errEndOfFile: return [NSString stringWithFormat:@"%s (%d)", "errEndOfFile", code];
			case errIO: return [NSString stringWithFormat:@"%s (%d)", "IO error", code];
			case errInvalidAttributesFile: return [NSString stringWithFormat:@"%s (%d)", "invalid attributes file", code];
			case errInvalidOperation: return [NSString stringWithFormat:@"%s (%d)", "invalid operation", code];
			case errDataTooLarge: return [NSString stringWithFormat:@"%s (%d)", "data too large", code];
			case errCouldNotConvertPathToURL: return [NSString stringWithFormat:@"%s (%d)", "could not convert path to URL", code];
			case errCouldNotConvertURLToFSRef: return [NSString stringWithFormat:@"%s (%d)", "could not convert URL to FSRef", code];
			case errCouldNotConvertFSRefToURL: return [NSString stringWithFormat:@"%s (%d)", "could not convert FSRef to URL", code];
			case errOutOfBounds: return [NSString stringWithFormat:@"%s (%d)", "out of bounds", code];
			case errInvalidSectorChecksumData: return [NSString stringWithFormat:@"%s (%d)", "invalid sector checksum data", code];
			case errInvalidSectorChecksum: return [NSString stringWithFormat:@"%s (%d)", "invalid sector checksum", code];
			case errInvalidSignature: return [NSString stringWithFormat:@"%s (%d)", "invalid signature", code];
			default: abort();
		}
	} else if ([[self domain] isEqualToString:NSPOSIXErrorDomain]) {
		return [NSString stringWithFormat:@"%s (%d)", strerror((int)code), code];
	}
	
	return [super localizedDescription];
}

@end
