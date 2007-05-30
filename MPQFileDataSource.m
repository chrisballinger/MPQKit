//
//  MPQFileDataSource.m
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
#import "MPQFileDataSource.h"


@implementation MPQFileDataSource

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
