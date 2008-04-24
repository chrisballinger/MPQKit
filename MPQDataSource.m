//
//  MPQDataSource.m
//  MPQKit
//
//  Created by Jean-François Roy on 23/05/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#if !defined(__APPLE__)
#define _XOPEN_SOURCE 600
#define _FILE_OFFSET_BITS  64
#endif

#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>
#import <sys/types.h>

#import "PHSErrorMacros.h"
#import "MPQErrors.h"
#import "MPQDataSource.h"


@implementation MPQDataSourceProxy

- (id)initWithData:(NSData*)data error:(NSError**)error {
    self = [super init];
    if (!self) ReturnValueWithError(nil, MPQErrorDomain, errOutOfMemory, nil, error)
    
    _backingStoreType = NSDataBackingStore;
    _dataBackingStore = [data retain];
    
    ReturnValueWithNoError(self, error)
}

- (id)initWithPath:(NSString*)path error:(NSError**)error {
    self = [super init];
    if (!self) ReturnValueWithError(nil, MPQErrorDomain, errOutOfMemory, nil, error)
    
    _backingStoreType = FileDescriptorBackingStore;
    
#if defined(__APPLE__)
    const char *cPath = [path fileSystemRepresentation];
    CFURLRef fileURLRef = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8*)cPath, strlen(cPath) + 1, false);
    if (fileURLRef == NULL) ReturnFromInitWithError(MPQErrorDomain, errCouldNotConvertPathToURL, nil, error)
    
    FSRef pathRef;
    Boolean ok = CFURLGetFSRef(fileURLRef, &pathRef);
    CFRelease(fileURLRef);
    if (ok == false) ReturnFromInitWithError(MPQErrorDomain, errCouldNotConvertURLToFSRef, nil, error)
    
    OSErr oerr = FSNewAliasMinimal(&pathRef, &_fileAlias);
    if (oerr != noErr) ReturnFromInitWithError(NSOSStatusErrorDomain, oerr, nil, error)
#else
    _path = [path copy];
#endif
    
    ReturnValueWithNoError(self, error)
}

- (void)dealloc {
    switch(_backingStoreType) {
        case NSDataBackingStore:
            [_dataBackingStore release];
            _dataBackingStore = nil;
            break;
        case FileDescriptorBackingStore:
#if defined(__APPLE__)
            if (_fileAlias != NULL) DisposeHandle((Handle)_fileAlias);
            _fileAlias = NULL;
#else
            [_path release];
			 _path = nil;
#endif
            break;
        default:
            abort();
    }
    
    [super dealloc];
}

- (id)createActualDataSource:(NSError**)error {
#if defined(__APPLE__)
    OSErr oerr;
    Boolean wasChanged;
    FSRef fileRef;
    CFURLRef urlRef;
#endif
    id dataSource;
    
    switch(_backingStoreType) {
        case NSDataBackingStore:
            return [[MPQDataSource alloc] initWithData:_dataBackingStore error:error];
        case FileDescriptorBackingStore:
#if defined(__APPLE__)
            oerr = FSResolveAliasWithMountFlags(NULL, _fileAlias, &fileRef, &wasChanged, kResolveAliasFileNoUI);
            if (oerr != noErr) ReturnValueWithError(nil, NSOSStatusErrorDomain, oerr, nil, error)
            urlRef = CFURLCreateFromFSRef(NULL, &fileRef);
            if (urlRef == NULL) ReturnValueWithError(nil, MPQErrorDomain, errCouldNotConvertFSRefToURL, nil, error)
            dataSource = [[MPQDataSource alloc] initWithURL:(NSURL*)urlRef error:error];
            CFRelease(urlRef);
#else
            dataSource = [[MPQDataSource alloc] initWithPath:_path error:error];
#endif
            return dataSource;
        default:
            abort();
    }
}

@end

@implementation MPQDataSource

- (id)initWithData:(NSData*)data error:(NSError**)error {
    self = [super init];
    if (!self) ReturnValueWithError(nil, MPQErrorDomain, errOutOfMemory, nil, error)
    
    _backingStoreType = NSDataBackingStore;
    _dataBackingStore = [data retain];
    
    ReturnValueWithNoError(self, error)
}

- (id)initWithPath:(NSString*)path error:(NSError**)error {
    self = [super init];
    if (!self) ReturnValueWithError(nil, MPQErrorDomain, errOutOfMemory, nil, error)
    
    _backingStoreType = FileDescriptorBackingStore;
    _fileDescriptorBackingStore = open([path fileSystemRepresentation], O_RDONLY, 0);
    if (_fileDescriptorBackingStore == -1) ReturnFromInitWithError(NSPOSIXErrorDomain, errno, nil, error)
    
    ReturnValueWithNoError(self, error)
}

- (id)initWithURL:(NSURL*)url error:(NSError**)error {
    return [self initWithPath:[url path] error:error];
}

- (void)dealloc {
    switch(_backingStoreType) {
        case NSDataBackingStore:
            [_dataBackingStore release];
            _dataBackingStore = nil;
            break;
        case FileDescriptorBackingStore:
            if (_fileDescriptorBackingStore != -1) close(_fileDescriptorBackingStore);
            _fileDescriptorBackingStore = -1;
            break;
        default:
            abort();
    }
    
    [super dealloc];
}

- (off_t)length:(NSError**)error {
    struct stat sb;
    switch(_backingStoreType) {
        case NSDataBackingStore:
            ReturnValueWithNoError((off_t)[_dataBackingStore length], error)
        case FileDescriptorBackingStore:
            if (fstat(_fileDescriptorBackingStore, &sb) == -1) ReturnValueWithPOSIXError(-1, nil, error)
            ReturnValueWithNoError(sb.st_size, error)
        default:
            abort();
    }
}

- (ssize_t)pread:(void*)buffer size:(size_t)size offset:(off_t)offset error:(NSError**)error {
    ssize_t bytes_read = 0;
    off_t length = [self length:error];
    if (length == -1) return -1;
    if (offset + size > (size_t)length) size = (size_t)(length - offset);
    if (size == 0) ReturnValueWithNoError(0, error)
    
    switch(_backingStoreType) {
        case NSDataBackingStore:
			// unsigned long will do the right thing on Mac OS X, since the 64-bit ABIs are using the LP64 model
            [_dataBackingStore getBytes:buffer range:NSMakeRange((unsigned long)offset, size)];
            ReturnValueWithNoError((ssize_t)size, error)
        case FileDescriptorBackingStore:
            bytes_read = pread(_fileDescriptorBackingStore, buffer, size, offset);
            if (bytes_read == -1) ReturnValueWithPOSIXError(-1, nil, error)
            ReturnValueWithNoError(bytes_read, error)
        default:
            abort();
    }
}

@end
