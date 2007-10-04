//
//  MPQFileSystem.h
//  MPQKit
//
//  Created by Jean-François Roy on 26/03/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//  Largely inspired from FUSEObjC, but without any dependency on non-daemon safe frameworks.
//

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <MPQKit/MPQKit.h>

@class MPQFSTree;

@interface MPQFileSystem : NSObject {
    NSString *mountPoint_;
    
    MPQArchive *archive_;
    MPQFSTree *archiveTree_;
    
    struct fuse_args *arguments_;
    BOOL overwriteVolname;
    
    BOOL isMounted_;
}

- (id)initWithArchive:(MPQArchive *)archive mountPoint:(NSString *)mnt arguments:(struct fuse_args *)arguments error:(NSError **)error;
- (void)startFuse;

@end
