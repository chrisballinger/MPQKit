//
//  MPQFileSystem.m
//  MPQKit
//
//  Created by Jean-François Roy on 26/03/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#import "MPQFileSystem.h"
#import "PHSErrorMacros.h"

#import <string.h>
#import <stdio.h>
#import <stdlib.h>

#import <errno.h>
#import <fcntl.h>
#import <unistd.h>

#import <sys/param.h>
#import <sys/mount.h>

#define FUSE_USE_VERSION 26
#define _FILE_OFFSET_BITS 64
#import <fuse.h>

static MPQFileSystem *manager;

static void mpqfs_dupargs(struct fuse_args *dest, struct fuse_args *src) {
    assert(dest);
    assert(src);
    
    dest->argc = src->argc;
    dest->argv = calloc(dest->argc, sizeof(char *));
    for (int i = 0; i < dest->argc; i++) {
        if (src->argv[i]) dest->argv[i] = strdup(src->argv[i]);
    }
    dest->allocated = 1;
}


@interface MPQFSTree : NSObject {
    MPQFSTree *parent_;
    NSString *name_;
    NSMutableDictionary *subtrees_;
    NSMutableDictionary *attributes;
}

- (NSString *)name;

- (MPQFSTree *)subtreeForName:(NSString *)name create:(BOOL)create;
- (NSArray *)subtrees;
- (NSEnumerator *)subtreeEnumerator;

- (uint32_t)totalNodeCount;
- (MPQFSTree *)findSubtree:(NSString *)path;

@end

@implementation MPQFSTree

- (id)init {
    self = [super init];
    if (!self) return nil;
    
    name_ = nil;
    parent_ = nil;
    subtrees_ = [NSMutableDictionary new];
    attributes = [NSMutableDictionary new];
    
    return self;
}

- (void)dealloc {
    NSEnumerator *subtreeEnum = [subtrees_ objectEnumerator];
    MPQFSTree *subtree;
    while ((subtree = [subtreeEnum nextObject])) {
        subtree->parent_ = nil;
    }
    
    [name_ release];
    [subtrees_ release];
    [attributes release];
    
    [super dealloc];
}

- (NSString *)name {
    return name_;
}

- (MPQFSTree *)subtreeForName:(NSString *)name create:(BOOL)create {
    NSString *key = [name uppercaseString];
    
    MPQFSTree *subtree = [subtrees_ objectForKey:key];
    if (!subtree && create) {
        subtree = [MPQFSTree new];
        subtree->name_ = [name copy];
        subtree->parent_ = self;
        [subtrees_ setObject:subtree forKey:key];
        [subtree release];
    }
    
    return subtree;
}

- (NSArray *)subtrees {
    return [subtrees_ allValues];
}

- (NSEnumerator *)subtreeEnumerator {
    return [subtrees_ objectEnumerator];
}

- (void)deleteSubtreeWithName:(NSString *)name {
    NSString *key = [name uppercaseString];
    [subtrees_ removeObjectForKey:key];
}

- (uint32_t)totalNodeCount {
    uint32_t n = (uint32_t)[subtrees_ count];
    
    NSEnumerator *subtreeEnum = [subtrees_ objectEnumerator];
    MPQFSTree *subtree;
    while ((subtree = [subtreeEnum nextObject])) {
        n += [subtree totalNodeCount];
    }
    
    return n;
}

- (MPQFSTree *)findSubtreeComponents_:(NSMutableArray *)components {
    id node = nil;
    uint32_t componentCount = [components count];
    
    if ([components count] == 0) return self;
    if ([[components lastObject] length] == 0) [components removeLastObject];
    if ([components count] == 0) return self;
    if ([[components objectAtIndex:0] length] == 0) [components removeObjectAtIndex:0];
    if ([components count] == 0) return self;
    
    NSString *nodeName = [components objectAtIndex:0];
    node = [subtrees_ objectForKey:nodeName];
    if (node) {
        if (componentCount == 1) return node;
        
        [components removeObjectAtIndex:0];
        return [(MPQFSTree *)node findSubtreeComponents_:components];
    }
    
    return nil;
}

- (MPQFSTree *)findSubtree:(NSString *)path {
    NSArray *components = [[path uppercaseString] componentsSeparatedByString:@"\\"];
    return [self findSubtreeComponents_:[[components mutableCopy] autorelease]];
}

@end


@implementation MPQFileSystem

- (BOOL)buildTree_:(NSError **)error {
    archiveTree_ = [[MPQFSTree alloc] init];
    
    // Load the internal listfile
    if (![archive_ loadInternalListfile:error]) return NO;
    
    NSAutoreleasePool *p = [NSAutoreleasePool new];
    NSLocale *locale = [NSLocale currentLocale];
    
    NSEnumerator *fileInfoEnumerator = [archive_ fileInfoEnumerator];
    NSDictionary *fileInfo;
    while ((fileInfo = [fileInfoEnumerator nextObject])) {
        NSString *filename = [fileInfo objectForKey:MPQFilename];
        if (!filename) continue;
        if (![[fileInfo objectForKey:MPQFileCanOpenWithoutFilename] boolValue]) continue;
        
        NSLocale *file_locale = [MPQArchive localeForMPQLocale:[[fileInfo objectForKey:MPQFileLocale] unsignedShortValue]];
        if (file_locale) {
            NSString *file_locale_id = [locale displayNameForKey:NSLocaleIdentifier value:[file_locale objectForKey:NSLocaleIdentifier]];
            if (!file_locale_id) file_locale_id = [file_locale localeIdentifier];
            NSString *extension = [filename pathExtension];
            filename = [NSString stringWithFormat:@"%@ - %@%@%@", 
                [filename stringByDeletingPathExtension], file_locale_id, ([extension length] == 0) ? @"" : @".", extension];
        }
        
        MPQFSTree *current_tree = archiveTree_;
        NSArray *components = [filename componentsSeparatedByString:@"\\"];
        
        NSEnumerator *nodeEnumerator = [components objectEnumerator];
        NSString *node;
        while ((node = [nodeEnumerator nextObject])) {
            current_tree = [current_tree subtreeForName:node create:YES];
        }
        
        [current_tree setValue:[fileInfo objectForKey:MPQFileHashPosition] forKeyPath:@"attributes.position"];
    }
    
    [p release];
    ReturnValueWithNoError(YES, error)
}

- (id)initWithArchive:(MPQArchive *)archive mountPoint:(NSString *)mnt arguments:(struct fuse_args *)arguments error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    
    archive_ = [archive retain];
    mountPoint_ = [mnt retain];
    arguments_ = arguments;
    
    overwriteVolname = NO;
    mountIcon = nil;
    
    isMounted_ = NO;
    
    if (![self buildTree_:error]) {
        [self release];
        return nil;
    }
    
    fuse_opt_add_arg(arguments_, "-oping_diskarb,rdonly,hard_remove,noauto_cache");
    fuse_opt_add_arg(arguments_, "-s");
    
    ReturnValueWithNoError(self, error)
}

- (void)dealloc {
    [archive_ release];
    [mountPoint_ release];
    [archiveTree_ release];
    
    fuse_opt_free_args(arguments_);
    
    [mountIcon release];    
    [super dealloc];
}

- (NSString *)mountName {
    return @"MPQFS";
}

- (NSString *)mountPoint {
    return [[mountPoint_ copy] autorelease];
}

#pragma mark Finder icon

- (NSData *)resourceHeaderWithFlags:(UInt16)flags {
    char header[82] = {
        0x00, 0x05, 0x16, 0x07, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x09, 0x00, 0x00,
        0x00, 0x32, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x52, 0xFF, 0xFF,
        0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00};
    
    FileInfo info;
    memset(&info, 0, sizeof(FileInfo));
    info.finderFlags = flags;
    info.finderFlags = EndianU16_NtoB(info.finderFlags);
    
    memset(header + 0x2E, 0, sizeof(UInt32));
    memcpy(header + 0x32, &info, sizeof(FileInfo));
    return [NSData dataWithBytes:&header length:82];
}

- (NSString *)resourcePathForPath:(NSString *)path {
    NSString *name = [path lastPathComponent];
    path = [path stringByDeletingLastPathComponent];
    name = [@"._" stringByAppendingString:name];
    path = [path stringByAppendingPathComponent:name];
    return path;
}

#pragma mark Initialization

- (void)fuseInit {
    isMounted_ = YES;
}

- (void)fuseDestroy {
    isMounted_ = NO;
}

#pragma mark Information

- (int)fillStatvfsBuffer:(struct statvfs *)stbuf forPath:(NSString *)path {
    // TODO: Should we have memset the statbuf to zero, or does fuse pre-fill values?
    NSDictionary *archive_info = [archive_ archiveInfo];
    
    // Block size
    stbuf->f_bsize = stbuf->f_frsize = 512 << [[archive_info objectForKey:MPQSectorSizeShift] unsignedIntValue];
    
    // Size in blocks
    struct stat sb;
    if (stat([[archive_ path] fileSystemRepresentation], &sb) == -1) return -errno;
    stbuf->f_blocks = (sb.st_size % stbuf->f_frsize == 0) ? sb.st_size / stbuf->f_frsize : (sb.st_size / stbuf->f_frsize) + 1;
    
    // Number of free / available blocks
    stbuf->f_bfree = stbuf->f_bavail = 0;
    
    // Number of nodes
    stbuf->f_files = [archiveTree_ totalNodeCount];
    
    // Number of free / available nodes
    stbuf->f_ffree = stbuf->f_favail = 0;
    
    // Maximum length of filenames
    stbuf->f_namemax = MPQ_MAX_PATH;
    
    return 0;
}

- (int)fillStatBuffer:(struct stat *)stbuf withFileInfo:(NSDictionary *)fileInfo isDirectory:(BOOL)isDirectory {
    assert(fileInfo);
    
    // Permissions (mode)
    if (isDirectory) stbuf->st_mode = S_IRUSR | S_IRGRP | S_IROTH | S_IXUSR | S_IXGRP | S_IXOTH | S_IFDIR;
    else stbuf->st_mode = S_IRUSR | S_IRGRP | S_IROTH | S_IFREG;
    
    // nlink
    stbuf->st_nlink = (isDirectory) ? 2 : 1;
    
    // Owner and Group
    stbuf->st_uid = geteuid();
    stbuf->st_gid = getegid();
    
    // TODO: For the timespec, there is a .tv_nsec (= nanosecond) part as well.
    // Since the NSDate returns a double, we can fill this in as well.
    
    // TODO: Fill mdate, atime, ctime from the MPQ time attribute
    NSDate *cdate = [fileInfo objectForKey:@"CreationDate"];
    
    // mtime, atime
//    if (mdate) {
//        time_t t = (time_t) [mdate timeIntervalSince1970];
//        stbuf->st_mtimespec.tv_sec = t;
//        stbuf->st_atimespec.tv_sec = t;
//    }
    
    // ctime  TODO: ctime is not "creation time" rather it's the last time the 
    // inode was changed.  mtime would probably be a closer approximation.
    if (cdate) {
        stbuf->st_ctimespec.tv_sec = [cdate timeIntervalSince1970];
    }
    
    // Size for regular files.
    if (!isDirectory) {
        stbuf->st_size = [[fileInfo objectForKey:MPQFileSize] unsignedIntValue];
    }
    
    // Set the number of blocks used so that Finder will display size on disk 
    // properly.
    // TODO: The stat man page says that st_blocks is "actual number of blocks 
    // allocated for the file in 512-byte units".  Investigate whether this is a
    // man mis-print, since I suspect it should be the statvfs f_frsize? 
    if (stbuf->st_size > 0) {
        stbuf->st_blocks = stbuf->st_size / 512;
        if (stbuf->st_size % 512) {
            ++(stbuf->st_blocks);
        }
    }
    
    return 0;
}

- (int)fillStatBuffer:(struct stat *)stbuf forPath:(NSString *)path {
    MPQFSTree *node = [archiveTree_ findSubtree:[path stringByReplacingSlashWithBackslash]];
    if (!node) return -ENOENT;
    BOOL isDirectory = ([[node subtrees] count] == 0) ? NO : YES;
    
    // Get file information from the archive
    NSDictionary *fileInfo = [NSDictionary dictionary];
    if (!isDirectory) fileInfo = [archive_ fileInfoForPosition:[[node valueForKeyPath:@"attributes.position"] unsignedIntValue]];
    
    return [self fillStatBuffer:stbuf withFileInfo:fileInfo isDirectory:isDirectory];
}

#pragma mark Open/Close

- (MPQFile *)openFileAtPath:(NSString *)path mode:(int)mode error:(NSError **)error {
    if (mode & (O_WRONLY | O_RDWR | O_APPEND | O_CREAT | O_TRUNC)) ReturnValueWithError(nil, NSPOSIXErrorDomain, EROFS, nil, error)
    
    MPQFSTree *node = [archiveTree_ findSubtree:[path stringByReplacingSlashWithBackslash]];
    if (!node) ReturnValueWithError(nil, NSPOSIXErrorDomain, ENOENT, nil, error)
    
    BOOL isDirectory = ([[node subtrees] count] == 0) ? NO : YES;
    if (isDirectory) ReturnValueWithError(nil, NSPOSIXErrorDomain, EISDIR, nil, error)
    
    MPQFile *file = [[archive_ openFileAtPosition:[[node valueForKeyPath:@"attributes.position"] unsignedIntValue] error:nil] retain];
    if (!file) ReturnValueWithError(nil, NSPOSIXErrorDomain, ENOENT, nil, error)
    ReturnValueWithNoError(file, error)
}

- (void)releaseFileAtPath:(NSString *)path handle:(MPQFile *)handle {
    [handle release];
}

#pragma mark Reading

- (NSArray *)fullDirectoryContentsAtPath:(NSString *)path error:(NSError **)error {
    MPQFSTree *node = [archiveTree_ findSubtree:[path stringByReplacingSlashWithBackslash]];
    BOOL isDirectory = ([[node subtrees] count] == 0) ? NO : YES;
    if (!isDirectory) ReturnValueWithError(nil, NSPOSIXErrorDomain, ENOTDIR, nil, error)
    
    NSMutableArray *fullContents = [NSMutableArray array];
    [fullContents addObject:@"."];
    [fullContents addObject:@".."];
    
    NSEnumerator *subtreeEnum = [node subtreeEnumerator];
    while ((node = [subtreeEnum nextObject])) {
        [fullContents addObject:[node name]];
    }
    
    ReturnValueWithNoError(fullContents, error)
}

- (int)readFileAtPath:(NSString *)path handle:(MPQFile *)handle buffer:(char *)buffer size:(size_t)size offset:(off_t)offset {
    [handle seekToFileOffset:offset];
    ssize_t bytes_read = [handle read:buffer size:size error:nil];
    if (bytes_read == -1) return -EIO;
    return bytes_read;
}

#pragma mark Writing

- (int)createDirectoryAtPath:(NSString *)path attributes:(NSDictionary *)attributes {
    return -EROFS;
}

- (int)createFileAtPath:(NSString *)path contents:(NSData *)contents attributes:(NSDictionary *)attributes {
    return -EROFS;
}

- (int)createSymbolicLinkAtPath:(NSString *)path pathContent:(NSString *)otherPath {
    return -EROFS; 
}

- (int)linkPath:(NSString *)source toPath:(NSString *)destination handler:(id)handler {
    return -EROFS; 
}

- (int)createFileAtPath:(NSString *)path attributes:(NSDictionary *)attributes {
    return -EROFS;
}

- (int)writeFileAtPath:(NSString *)path handle:(MPQFile *)handle buffer:(const char *)buffer size:(size_t)size offset:(off_t)offset {
    return -EROFS;
}

- (int)truncateFileAtPath:(NSString *)path offset:(off_t)offset {
    return -EROFS;
}

- (int)movePath:(NSString *)source toPath:(NSString *)destination handler:(id)handler {
    return -EROFS;
}

- (int)removeFileAtPath:(NSString *)path handler:(id)handler { 
    return -EROFS;
}

#pragma mark FUSE operations

+ (MPQFileSystem *)currentManager {
    return manager; //[[[NSThread currentThread] threadDictionary] objectForKey:@"FUSE Manager"];
}

static void *fusefm_init(struct fuse_conn_info *conn) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    MPQFileSystem *manager = [MPQFileSystem currentManager];
    NSCAssert1(manager, @"No manager set for fuse thread %@!", [NSThread currentThread]);
    
    [manager fuseInit];
    
    [pool release];
    return manager;
}


static void fusefm_destroy(void *private_data) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    [[MPQFileSystem currentManager] fuseDestroy];
    [pool release];
}

static int fusefm_statfs(const char* path, struct statvfs* stbuf) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    int res = 0;
    memset(stbuf, 0, sizeof(struct statvfs));
    
    res = [[MPQFileSystem currentManager] fillStatvfsBuffer:stbuf forPath:[NSString stringWithUTF8String:path]];
    
    [pool release];
    return res;
}

static int fusefm_getattr(const char *path, struct stat *stbuf) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    int res = 0;
    memset(stbuf, 0, sizeof(struct stat));
    
    res = [[MPQFileSystem currentManager] fillStatBuffer:stbuf forPath:[NSString stringWithUTF8String:path]];
    
    [pool release];
    return res;
}

int fusefm_setattr(const char *path, const char *a, const char *b, size_t c, int d) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    // TODO: Body :-)
    [pool release];  
    return 0;
}

static int fusefm_fgetattr(const char *path, struct stat *stbuf, struct fuse_file_info *fi) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    int res = 0;
    memset(stbuf, 0, sizeof(struct stat));
    
    MPQFile *file = (MPQFile *)(unsigned long)(fi->fh);
    res = [[MPQFileSystem currentManager] fillStatBuffer:stbuf withFileInfo:[file fileInfo] isDirectory:NO];
    
    [pool release];
    return res;
}

static int fusefm_readdir(const char *path, void *buf, fuse_fill_dir_t filler, off_t offset, struct fuse_file_info *fi) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    NSError *error = nil;
    
    NSArray *contents = [[MPQFileSystem currentManager] fullDirectoryContentsAtPath:[NSString stringWithUTF8String:path] error:&error];
    if (!contents) {
        [pool release];
        return -[error code];
    }
    
    for (int i = 0, count = [contents count]; i < count; i++) {
        filler(buf, [[contents objectAtIndex:i] UTF8String], NULL, 0);
    }
    
    [pool release];
    return 0;
}

static int fusefm_create(const char* path, mode_t mode, struct fuse_file_info* fi) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    
    int res = [[MPQFileSystem currentManager] createFileAtPath:[NSString stringWithUTF8String:path] attributes:nil];
    
    [pool release];
    return res;
}

static int fusefm_unlink(const char* path) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    int ret = [[MPQFileSystem currentManager] removeFileAtPath:[NSString stringWithUTF8String:path] handler:nil];
    
    [pool release];
    return ret;
}

static int fusefm_rename(const char* path, const char* toPath) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    NSString* source = [NSString stringWithUTF8String:path];
    NSString* destination = [NSString stringWithUTF8String:toPath];
    int ret = [[MPQFileSystem currentManager] movePath:source toPath:destination handler:nil];
    
    [pool release];
    return ret;
    
}

static int fusefm_truncate(const char* path, off_t offset) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    
    int res = [[MPQFileSystem currentManager] truncateFileAtPath:[NSString stringWithUTF8String:path] offset:offset];
    
    [pool release];
    return res;
}

static int fusefm_mkdir(const char* path, mode_t mode) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    int ret = [[MPQFileSystem currentManager] createDirectoryAtPath:[NSString stringWithUTF8String:path] attributes:nil];
    
    [pool release];
    return ret;
}

static int fusefm_rmdir(const char* path) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    int ret = [[MPQFileSystem currentManager] removeFileAtPath:[NSString stringWithUTF8String:path] handler:nil];
    
    [pool release];
    return ret;
}

static int fusefm_chown(const char* path, uid_t uid, gid_t gid) {
    return -ENOSYS;
}

static int fusefm_chmod(const char* path, mode_t mode) {
    return -ENOSYS;
}

static int fusefm_open(const char *path, struct fuse_file_info *fi) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    NSError *error = nil;
    
    id object = [[MPQFileSystem currentManager] openFileAtPath:[NSString stringWithUTF8String:path] mode:fi->flags error:&error];
    if (object == nil) {
        [pool release];
        return -[error code];
    }
    fi->fh = (unsigned long)object;
    
    [pool release];
    return 0;
}

static int fusefm_release(const char *path, struct fuse_file_info *fi) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    [[MPQFileSystem currentManager] releaseFileAtPath:[NSString stringWithUTF8String:path] handle:(MPQFile *)(unsigned long)fi->fh];
    
    [pool release];
    return 0;
}

static int fusefm_read(const char *path, char *buf, size_t size, off_t offset, struct fuse_file_info *fi) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    
    int length = [[MPQFileSystem currentManager] readFileAtPath:[NSString stringWithUTF8String:path]
                                                         handle:(MPQFile *)(unsigned long)fi->fh
                                                         buffer:buf
                                                           size:size
                                                         offset:offset];
    [pool release];
    return length;
}

static int fusefm_write(const char* path, const char* buf, size_t size, off_t offset, struct fuse_file_info* fi) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    
    int length = [[MPQFileSystem currentManager] writeFileAtPath:[NSString stringWithUTF8String:path]
                                                          handle:(id)(unsigned long)fi->fh
                                                          buffer:buf
                                                            size:size
                                                          offset:offset];
    
    [pool release];
    return length;
}

static int fusefm_ftruncate(const char* path, off_t offset, struct fuse_file_info *fh) {
    return fusefm_truncate(path, offset);
}

static int fusefm_readlink(const char *path, char *buf, size_t size) {
    return -ENOSYS;
}

#pragma mark FUSE operation structure

static struct fuse_operations fusefm_operations = {
    // Initialzation and termination
    .init = fusefm_init,
    .destroy = fusefm_destroy,
    
    // File information
    .statfs = fusefm_statfs,
    .getattr = fusefm_getattr,
    //.setattr = fusefm_setattr,
    .fgetattr = fusefm_fgetattr,
    
    // Directory operations
    .readdir = fusefm_readdir,
    .create = fusefm_create,
    .unlink = fusefm_unlink,
    .rename = fusefm_rename,
    .truncate = fusefm_truncate,
    .mkdir = fusefm_mkdir,
    .rmdir = fusefm_rmdir,
    
    // Permissions
    .chown = fusefm_chown,
    .chmod = fusefm_chmod,
    
    // File operations
    .open = fusefm_open,
    .release = fusefm_release,
    .read = fusefm_read,
    .write = fusefm_write,
    .ftruncate = fusefm_ftruncate,
    
    // Links
    .readlink = fusefm_readlink,
    
    // Extended attributes
    //.setxattr = fusefm_setxattr,
    //.getxattr = fusefm_getxattr,
    //.listxattr = fusefm_listxattr,
    //.removexattr = fusefm_removexattr,
};

#pragma mark Mount

- (void)startFuse {
    if (mountIcon) {
        [archive_ addFileWithPath:mountIcon filename:@".VolumeIcon.icns" parameters:nil error:nil];
        NSNumber *position = [[archive_ fileInfoForFile:@".VolumeIcon.icns" locale:MPQNeutral] objectForKey:MPQFileHashPosition];
        [[archiveTree_ subtreeForName:@".VolumeIcon.icns" create:YES] setValue:position forKeyPath:@"attributes.position"];
        
        NSData *volumeHeader = [self resourceHeaderWithFlags:kHasCustomIcon];
        [volumeHeader writeToFile:[self resourcePathForPath:mountPoint_] options:0 error:nil];
    }
    
    struct fuse_args args;
    mpqfs_dupargs(&args, arguments_);
    
    const char *flub = [[NSString stringWithFormat:@"-ovolname=%@", [[archive_ path] lastPathComponent]] UTF8String];
    if (overwriteVolname) fuse_opt_add_arg(&args, flub);
    
    manager = self;
    fuse_main(args.argc, args.argv, &fusefm_operations, NULL);
    manager = nil;
    
    if (mountIcon) {
        [[NSFileManager defaultManager] removeFileAtPath:[self resourcePathForPath:mountPoint_] handler:nil];
        [archiveTree_ deleteSubtreeWithName:@".VolumeIcon.icns"];
        [archive_ undoLastOperation:nil];
    }
    
    fuse_opt_free_args(arguments_);
}

@end
