//
//  MPQDataSource.m
//  MPQKit
//
//  Created by Jean-François Roy on 23/05/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

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
    if (!self)
        ReturnValueWithError(nil, MPQErrorDomain, errOutOfMemory, nil, error)
    
    _backingStoreType = NSDataBackingStore;
    _dataBackingStore = [data retain];
    
    return self;
}

- (id)initWithPath:(NSString*)path error:(NSError**)error {
    self = [super init];
    if (!self)
        ReturnValueWithError(nil, MPQErrorDomain, errOutOfMemory, nil, error)
    
    _backingStoreType = FileDescriptorBackingStore;
    
    const char* cPath = path.fileSystemRepresentation;
    CFURLRef fileURLRef = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8*)cPath, strlen(cPath) + 1, false);
    if (fileURLRef == NULL)
        ReturnFromInitWithError(MPQErrorDomain, errCouldNotConvertPathToURL, nil, error)
    
    _fileAlias = CFURLCreateBookmarkDataFromFile(NULL, fileURLRef, NULL);
    CFRelease(fileURLRef);
    
    if (!_fileAlias) {
        ReturnFromInitWithError(MPQErrorDomain, errCouldNotConvertURLToFSRef, nil, error);
    }

    return self;
}

- (void)dealloc {
    switch(_backingStoreType) {
        case NSDataBackingStore:
            [_dataBackingStore release];
            _dataBackingStore = nil;
            break;
        case FileDescriptorBackingStore:
            if (_fileAlias != NULL)
                CFRelease(_fileAlias);
            _fileAlias = NULL;
            break;
        default:
            abort();
    }
    
    [super dealloc];
}

- (id)createActualDataSource:(NSError**)error {
    CFURLRef urlRef;
    id dataSource;
    
    switch(_backingStoreType) {
        case NSDataBackingStore:
            return [[MPQDataSource alloc] initWithData:_dataBackingStore error:error];
        case FileDescriptorBackingStore:
            urlRef = CFURLCreateByResolvingBookmarkData(NULL, _fileAlias, NULL, NULL, NULL, NULL, NULL);
            if (urlRef == NULL)
                ReturnValueWithError(nil, MPQErrorDomain, errCouldNotConvertFSRefToURL, nil, error)
            dataSource = [[MPQDataSource alloc] initWithURL:(NSURL*)urlRef error:error];
            CFRelease(urlRef);
            return dataSource;
        default:
            abort();
    }
}

@end

@implementation MPQDataSource

- (id)initWithData:(NSData*)data error:(NSError**)error {
    self = [super init];
    if (!self)
        ReturnValueWithError(nil, MPQErrorDomain, errOutOfMemory, nil, error)
    
    _backingStoreType = NSDataBackingStore;
    _dataBackingStore = [data retain];
    
    return self;
}

- (id)initWithPath:(NSString*)path error:(NSError**)error {
    self = [super init];
    if (!self)
        ReturnValueWithError(nil, MPQErrorDomain, errOutOfMemory, nil, error)
    
    _backingStoreType = FileDescriptorBackingStore;
    _fileDescriptorBackingStore = open(path.fileSystemRepresentation, O_RDONLY, 0);
    if (_fileDescriptorBackingStore == -1)
        ReturnFromInitWithError(NSPOSIXErrorDomain, errno, nil, error)
    
    return self;
}

- (id)initWithURL:(NSURL*)url error:(NSError**)error {
    return [self initWithPath:url.path error:error];
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
            return (off_t)_dataBackingStore.length;
        case FileDescriptorBackingStore:
            if (fstat(_fileDescriptorBackingStore, &sb) == -1) ReturnValueWithPOSIXError(-1, nil, error)
            return sb.st_size;
        default:
            abort();
    }
}

- (ssize_t)pread:(void*)buffer size:(size_t)size offset:(off_t)offset error:(NSError**)error {
    ssize_t bytes_read = 0;
    off_t length = [self length:error];
    if (length == -1)
        return -1;
    
    if (offset + size > (size_t)length)
        size = (size_t)(length - offset);
    if (size == 0)
        return 0;
    
    switch(_backingStoreType) {
        case NSDataBackingStore:
            // unsigned long will do the right thing on Mac OS X, since the 64-bit ABIs are using the LP64 model
            [_dataBackingStore getBytes:buffer range:NSMakeRange((unsigned long)offset, size)];
            return (ssize_t)size;
        case FileDescriptorBackingStore:
            bytes_read = pread(_fileDescriptorBackingStore, buffer, size, offset);
            if (bytes_read == -1)
                ReturnValueWithPOSIXError(-1, nil, error)
            return bytes_read;
        default:
            abort();
    }
}

@end
