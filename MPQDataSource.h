//
//  MPQDataSource.h
//  MPQKit
//
//  Created by Jean-François Roy on 23/05/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>
#if defined(__APPLE__)
#import <CoreServices/CoreServices.h>
#endif

enum {
    NSDataBackingStore = 1,
    FileDescriptorBackingStore = 2,
};
typedef uint8_t MPQDataSourceBackingStoreType;
    

@interface MPQDataSourceProxy : NSObject {
    MPQDataSourceBackingStoreType _backingStoreType;
    NSData *_dataBackingStore;
#if defined(__APPLE__)
    AliasHandle _fileAlias;
#else
    NSString *_path;
#endif
}

- (id)initWithData:(NSData*)data error:(NSError**)error;
- (id)initWithPath:(NSString*)path error:(NSError**)error;

- (id)createActualDataSource:(NSError**)error;

@end

@interface MPQDataSource : NSObject {
    MPQDataSourceBackingStoreType _backingStoreType;
    NSData *_dataBackingStore;
    int _fileDescriptorBackingStore;
}

- (id)initWithData:(NSData*)data error:(NSError**)error;
- (id)initWithPath:(NSString*)path error:(NSError**)error;
- (id)initWithURL:(NSURL*)url error:(NSError**)error;

- (off_t)length:(NSError**)error;
- (ssize_t)pread:(void*)buffer size:(size_t)size offset:(off_t)offset error:(NSError**)error;

@end
