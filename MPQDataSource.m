//
//  MPQDataSource.m
//  MPQKit
//
//  Created by Jean-François Roy on 23/05/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#import <unistd.h>
#import <sys/stat.h>
#import <sys/types.h>

#import "PHSErrorMacros.h"
#import "MPQErrors.h"
#import "MPQDataSource.h"


@implementation MPQDataSourceProxy

- (id)initWithData:(NSData *)data error:(NSError **)error {
    self = [super init];
    if (!self) ReturnValueWithError(nil, MPQErrorDomain, errOutOfMemory, nil, error)
    
    _backingStoreType = NSDataBackingStore;
    _dataBackingStore = [data retain];
    
    ReturnValueWithNoError(self, error)
}

- (id)initWithPath:(NSString *)path error:(NSError **)error {
    self = [super init];
    if (!self) ReturnValueWithError(nil, MPQErrorDomain, errOutOfMemory, nil, error)
    
    _backingStoreType = FileDescriptorBackingStore;
    
    const char *cPath = [path fileSystemRepresentation];
    CFURLRef fileURLRef = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)cPath, strlen(cPath) + 1, false);
    if (fileURLRef == NULL) ReturnFromInitWithError(MPQErrorDomain, errCouldNotConvertPathToURL, nil, error)
    
    FSRef pathRef;
    Boolean ok = CFURLGetFSRef(fileURLRef, &pathRef);
    CFRelease(fileURLRef);
    if (ok == false) ReturnFromInitWithError(MPQErrorDomain, errCouldNotConvertURLToFSRef, nil, error)
    
    OSErr oerr = FSNewAliasMinimal(&pathRef, &_fileAlias);
    if (oerr != noErr) ReturnFromInitWithError(NSOSStatusErrorDomain, oerr, nil, error)
    
    ReturnValueWithNoError(self, error)
}

- (void)dealloc {
    switch(_backingStoreType) {
        case NSDataBackingStore:
            [_dataBackingStore release];
            _dataBackingStore = nil;
        case FileDescriptorBackingStore:
            if (_fileAlias != NULL) DisposeHandle((Handle)_fileAlias);
            _fileAlias = NULL;
        default:
            abort();
    }
    
    [super dealloc];
}

- (id)createActualDataSource:(NSError **)error {
    OSErr oerr;
    Boolean wasChanged;
    FSRef fileRef;
    CFURLRef urlRef;
    
    switch(_backingStoreType) {
        case NSDataBackingStore:
            return [[MPQDataSource alloc] initWithData:_dataBackingStore error:error];
        case FileDescriptorBackingStore:
            oerr = FSResolveAliasWithMountFlags(NULL, _fileAlias, &fileRef, &wasChanged, kResolveAliasFileNoUI);
            if (oerr != noErr) ReturnValueWithError(nil, NSOSStatusErrorDomain, oerr, nil, error)
            urlRef = CFURLCreateFromFSRef(NULL, &fileRef);
            if (urlRef == NULL) ReturnValueWithError(nil, MPQErrorDomain, errCouldNotConvertFSRefToURL, nil, error)
            id dataSource = [[MPQDataSource alloc] initWithURL:(NSURL *)urlRef error:error];
            CFRelease(urlRef);
            return dataSource;
        default:
            abort();
    }
}

@end

@implementation MPQDataSource

- (id)initWithData:(NSData *)data error:(NSError **)error {
    self = [super init];
    if (!self) ReturnValueWithError(nil, MPQErrorDomain, errOutOfMemory, nil, error)
    
    _backingStoreType = NSDataBackingStore;
    _dataBackingStore = [data retain];
    
    ReturnValueWithNoError(self, error)
}

- (id)initWithPath:(NSString *)path error:(NSError **)error {
    self = [super init];
    if (!self) ReturnValueWithError(nil, MPQErrorDomain, errOutOfMemory, nil, error)
    
    _backingStoreType = FileDescriptorBackingStore;
    _fileDescriptorBackingStore = open([path fileSystemRepresentation], O_RDONLY, 0);
    if (_fileDescriptorBackingStore == -1) ReturnFromInitWithError(NSPOSIXErrorDomain, errno, nil, error)
    
    ReturnValueWithNoError(self, error)
}

- (id)initWithURL:(NSURL *)url error:(NSError **)error {
    return [self initWithPath:[url path] error:error];
}

- (void)dealloc {
    switch(_backingStoreType) {
        case NSDataBackingStore:
            [_dataBackingStore release];
            _dataBackingStore = nil;
        case FileDescriptorBackingStore:
            if (_fileDescriptorBackingStore != -1) close(_fileDescriptorBackingStore);
            _fileDescriptorBackingStore = -1;
        default:
            abort();
    }
    
    [super dealloc];
}

- (off_t)length:(NSError **)error {
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

- (ssize_t)pread:(void *)buffer size:(size_t)size offset:(off_t)offset error:(NSError **)error {
    ssize_t read_bytes = 0;
    off_t length = [self length:error];
    if (length == -1) return -1;
    if (offset + size > length) size = length - offset;
    if (size == 0) ReturnValueWithNoError(0, error)
    
    switch(_backingStoreType) {
        case NSDataBackingStore:
            [_dataBackingStore getBytes:buffer range:NSMakeRange(offset, size)];
            ReturnValueWithNoError((ssize_t)size, error)
        case FileDescriptorBackingStore:
            read_bytes = pread(_fileDescriptorBackingStore, buffer, size, offset);
            if (read_bytes < size) ReturnValueWithPOSIXError(read_bytes, nil, error)
            ReturnValueWithNoError(read_bytes, error)
        default:
            abort();
    }
}

@end
