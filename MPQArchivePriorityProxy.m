//
//  MPQArchivePriorityProxy.m
//  MPQKit
//
//  Created by Jean-Francois Roy on 01/07/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#if !defined(__APPLE__)
#define _XOPEN_SOURCE 500
#endif

#import <MPQKit/MPQKitPrivate.h>
#import "PHSErrorMacros.h"
#import "MPQArchivePriorityProxy.h"

struct _archive_binary_tree_node {
	MPQArchive *archive;
	struct _archive_binary_tree_node *next;
};

struct _archive_binary_tree {
	uint32_t priority;
	struct _archive_binary_tree_node *top;
};

static int _archive_binary_tree_compare(const void *v1, const void *v2) {
	struct _archive_binary_tree *t1 = (struct _archive_binary_tree*)v1;
	struct _archive_binary_tree *t2 = (struct _archive_binary_tree*)v2;
	
	if (t1->priority < t2->priority) return -1;
	if (t1->priority == t2->priority) return 0;
	return 1;
}


@implementation MPQArchivePriorityProxy

- (id)init {
	self = [super init];
	if (!self) return nil;
	
	_archives = calloc(0x10, sizeof(struct _archive_binary_tree));
	_priority_allocated = 0x10;
	_priority_count = 0;
	_archives_set = [[NSMutableSet alloc] initWithCapacity:0x20];
	
	return self;
}

- (void)dealloc {
	struct _archive_binary_tree *archives = (struct _archive_binary_tree*)_archives;
	for (uint32_t i = 0; i < _priority_count; i++) {
		struct _archive_binary_tree_node *next = archives[i].top;
		while (next) {
			struct _archive_binary_tree_node *current = next;
			[current->archive release];
			next = current->next;
			free(current);
		}
	}
	
	free(_archives);
	[_archives_set release];
	[super dealloc];
}

- (void)addArchive:(MPQArchive*)archive withPriority:(uint32_t)priority {
	struct _archive_binary_tree *archives = (struct _archive_binary_tree*)_archives;
	
	// Quick path for the first insertion
	if (_priority_count == 0) {
		archives[0].priority = priority;
		archives[0].top = malloc(sizeof(struct _archive_binary_tree_node));
		archives[0].top->archive = [archive retain];
		archives[0].top->next = NULL;
		_priority_count++;
		[_archives_set addObject:archive];
		return;
	}
	
	// Maitain the archive alive until we're done
	[archive retain];
	
	// If the archive is already in the tree, remove it first
	if ([_archives_set containsObject:archive]) [self removeArchive:archive];
	
	// Binary search to find the priority queue
	uint32_t l = 0;
	uint32_t r = _priority_count - 1;
	struct _archive_binary_tree *requested_priority_tree = NULL;
	
	while (l <= r) {
		uint32_t m = l + (r - l) / 2;
		if (priority == archives[m].priority) {
			requested_priority_tree = archives + m;
			break;
		}
		else if (priority < archives[m].priority) if (m == 0) break; else r = m - 1;
		else l = m + 1;
	}
	
	if (requested_priority_tree == NULL) {
		// Check if we need to grow the tree storage
		if (_priority_count == _priority_allocated - 1) {
			_priority_allocated += 0x10;
			_archives = realloc(_archives, _priority_allocated * sizeof(struct _archive_binary_tree));
			archives = (struct _archive_binary_tree*)_archives;
		}
		
		// Create the new priority
		archives[_priority_count].priority = priority;
		archives[_priority_count].top = malloc(sizeof(struct _archive_binary_tree_node));
		archives[_priority_count].top->archive = [archive retain];
		archives[_priority_count].top->next = NULL;
		_priority_count++;
		
		// Sort the tree
#if defined(__APPLE__)
		mergesort(archives, _priority_count, sizeof(struct _archive_binary_tree), _archive_binary_tree_compare);
#else
		qsort(archives, _priority_count, sizeof(struct _archive_binary_tree), _archive_binary_tree_compare);
#endif

	} else {
		// Push the archive at the top
		struct _archive_binary_tree_node *old = requested_priority_tree->top;
		requested_priority_tree->top = malloc(sizeof(struct _archive_binary_tree_node));
		requested_priority_tree->top->archive = [archive retain];
		requested_priority_tree->top->next = old;
	}
	
	// Add the archive to the archive set
	[_archives_set addObject:archive];
	[archive release];
}

- (void)removeArchive:(MPQArchive*)archive {
	struct _archive_binary_tree *archives = (struct _archive_binary_tree*)_archives;
	
	// Quick path if the tree is empty
	if (_priority_count == 0) return;
	
	// Quick check if the archive is in the priority tree
	if (![_archives_set containsObject:archive]) return;
	
	// Linear search for the archive
	for (uint32_t i = 0; i < _priority_count; i++) {
		struct _archive_binary_tree_node *next = archives[i].top;
		while (next) {
			struct _archive_binary_tree_node *current = next;
			if (current->archive == archive) {
				[current->archive release];
				next = current->next;
				if (current == archives[i].top) archives[i].top = next;
				free(current);
				[_archives_set removeObject:archive];
				return;
			}
		}
	}
}

- (MPQFile*)openFile:(NSString*)filename {
	return [self openFile:filename locale:MPQNeutral error:(NSError**)NULL];
}

- (MPQFile*)openFile:(NSString*)filename error:(NSError **)error {
	return [self openFile:filename locale:MPQNeutral error:error];
}

- (MPQFile*)openFile:(NSString*)filename locale:(MPQLocale)locale {
	return [self openFile:filename locale:locale error:(NSError**)NULL];
}

- (MPQFile*)openFile:(NSString*)filename locale:(MPQLocale)locale error:(NSError **)error {
    NSParameterAssert(filename != nil);
	NSError *local_error = nil;
    
    char *filename_cstring = _MPQCreateASCIIFilename(filename, error);
    if (!filename_cstring) return nil;
	
	struct _archive_binary_tree *archives = (struct _archive_binary_tree*)_archives;
	struct _archive_binary_tree_node *next = NULL;
	uint32_t hash_position = 0;
	for (uint32_t i = 0; i < _priority_count; i++) {
		next = archives[i].top;
		while (next) {
			// Find the file in the hash table
			hash_position = [next->archive findHashPosition:filename_cstring locale:locale error:&local_error];
			if (hash_position != 0xffffffff) break;
			else if ([[local_error domain] isEqual:MPQErrorDomain] && [local_error code] != errHashTableEntryNotFound) {
				free(filename_cstring);
				if (error) *error = local_error;
				return NO;
			}
			
			next = next->next;
		}
	}
	
	if (next == NULL) {
		free(filename_cstring);
		if (error) *error = local_error;
		return nil;
	}
	
	if (([next->archive _blockTable][[next->archive _hashTable][hash_position].block_table_index].flags & MPQFileStopSearchMarker)) {
		free(filename_cstring);
		if (error) *error = [NSError errorWithDomain:MPQErrorDomain code:errHashTableEntryNotFound userInfo:nil];
		return nil;
	}
	
	if (![next->archive _filenameTable][hash_position]) [next->archive _filenameTable][hash_position] = filename_cstring;
	else free(filename_cstring);
    
    // openFileAtPosition does the rest
    return [next->archive openFileAtPosition:hash_position error:error];
}

- (NSData*)copyDataForFile:(NSString*)filename {
    return [self copyDataForFile:filename range:NSMakeRange(0, 0) locale:MPQNeutral error:(NSError**)NULL];
}

- (NSData*)copyDataForFile:(NSString*)filename error:(NSError **)error {
    return [self copyDataForFile:filename range:NSMakeRange(0, 0) locale:MPQNeutral error:error];
}

- (NSData*)copyDataForFile:(NSString*)filename range:(NSRange)dataRange {
    return [self copyDataForFile:filename range:dataRange locale:MPQNeutral error:(NSError**)NULL];
}

- (NSData*)copyDataForFile:(NSString*)filename range:(NSRange)dataRange error:(NSError **)error {
    return [self copyDataForFile:filename range:dataRange locale:MPQNeutral error:error];
}

- (NSData*)copyDataForFile:(NSString*)filename locale:(MPQLocale)locale {
    return [self copyDataForFile:filename range:NSMakeRange(0, 0) locale:locale error:(NSError**)NULL];
}

- (NSData*)copyDataForFile:(NSString*)filename locale:(MPQLocale)locale error:(NSError **)error {
    return [self copyDataForFile:filename range:NSMakeRange(0, 0) locale:locale error:error];
}

- (NSData*)copyDataForFile:(NSString*)filename range:(NSRange)dataRange locale:(MPQLocale)locale {
    return [self copyDataForFile:filename range:dataRange locale:locale error:(NSError**)NULL];
}

- (NSData*)copyDataForFile:(NSString*)filename range:(NSRange)dataRange locale:(MPQLocale)locale error:(NSError **)error {
    MPQFile *theFile = [self openFile:filename locale:locale error:error];
    if (!theFile) return nil;
    
    NSData *returnData = nil;
    if (dataRange.length == 0) {
        [theFile seekToFileOffset:dataRange.location];
        returnData = [theFile copyDataToEndOfFile];
    } else {
        [theFile seekToFileOffset:dataRange.location];
		// Explicit cast is OK here, MPQ file sizes are 32-bit
        returnData = [theFile copyDataOfLength:(uint32_t)dataRange.length];
    }
    
    [theFile release];
    ReturnValueWithNoError(returnData, error)
}

- (BOOL)fileExists:(NSString*)filename {
	return [self fileExists:filename locale:MPQNeutral error:(NSError**)NULL];
}

- (BOOL)fileExists:(NSString*)filename error:(NSError **)error {
	return [self fileExists:filename locale:MPQNeutral error:error];
}

- (BOOL)fileExists:(NSString*)filename locale:(MPQLocale)locale {
    return [self fileExists:filename locale:locale error:(NSError**)NULL];
}

- (BOOL)fileExists:(NSString*)filename locale:(MPQLocale)locale error:(NSError **)error {
    NSParameterAssert(filename != nil);
	NSError *local_error = nil;
	
    char *filename_cstring = _MPQCreateASCIIFilename(filename, error);
    if (!filename_cstring) return NO;
    
	struct _archive_binary_tree *archives = (struct _archive_binary_tree*)_archives;
	for (uint32_t i = 0; i < _priority_count; i++) {
		struct _archive_binary_tree_node *next = archives[i].top;
		while (next) {
			// Find the file in the hash table
			uint32_t hash_position = [next->archive findHashPosition:filename_cstring locale:locale error:&local_error];
			if (hash_position != 0xffffffff) {
				if (![next->archive _filenameTable][hash_position]) [next->archive _filenameTable][hash_position] = filename_cstring;
				else free(filename_cstring);
				
				if (([next->archive _blockTable][[next->archive _hashTable][hash_position].block_table_index].flags & MPQFileStopSearchMarker)) {
					if (error) *error = [NSError errorWithDomain:MPQErrorDomain code:errHashTableEntryNotFound userInfo:nil];
					return NO;
				}
				
				if (error) *error = local_error;
				return YES;
			} else if ([[local_error domain] isEqual:MPQErrorDomain] && [local_error code] != errHashTableEntryNotFound) {
				free(filename_cstring);
				if (error) *error = local_error;
				return NO;
			}
			
			next = next->next;
		}
	}
	
	free(filename_cstring);
	if (error) *error = local_error;
	return NO;
}

@end
