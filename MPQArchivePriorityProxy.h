//
//  MPQArchivePriorityProxy.h
//  MPQKit
//
//  Created by Jean-Francois Roy on 01/07/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#import <stdint.h>
#import <Foundation/Foundation.h>


@interface MPQArchivePriorityProxy : NSObject {
	void *_archives;
	uint32_t _priority_count;
	uint32_t _priority_allocated;
	NSMutableSet *_archives_set;
}

- (void)addArchive:(MPQArchive*)archive withPriority:(uint32_t)priority;
- (void)removeArchive:(MPQArchive*)archive;

- (MPQFile*)openFile:(NSString*)filename;
- (MPQFile*)openFile:(NSString*)filename error:(NSError**)error;
- (MPQFile*)openFile:(NSString*)filename locale:(MPQLocale)locale;
- (MPQFile*)openFile:(NSString*)filename locale:(MPQLocale)locale error:(NSError**)error;

- (NSData*)copyDataForFile:(NSString*)filename;
- (NSData*)copyDataForFile:(NSString*)filename error:(NSError**)error;
- (NSData*)copyDataForFile:(NSString*)filename range:(NSRange)dataRange;
- (NSData*)copyDataForFile:(NSString*)filename range:(NSRange)dataRange error:(NSError**)error;
- (NSData*)copyDataForFile:(NSString*)filename locale:(MPQLocale)locale;
- (NSData*)copyDataForFile:(NSString*)filename locale:(MPQLocale)locale error:(NSError**)error;
- (NSData*)copyDataForFile:(NSString*)filename range:(NSRange)dataRange locale:(MPQLocale)locale;
- (NSData*)copyDataForFile:(NSString*)filename range:(NSRange)dataRange locale:(MPQLocale)locale error:(NSError**)error;

- (BOOL)fileExists:(NSString*)filename;
- (BOOL)fileExists:(NSString*)filename error:(NSError**)error;
- (BOOL)fileExists:(NSString*)filename locale:(MPQLocale)locale;
- (BOOL)fileExists:(NSString*)filename locale:(MPQLocale)locale error:(NSError**)error;

@end
