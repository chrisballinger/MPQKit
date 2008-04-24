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
#import <sys/types.h>

#define FUSE_USE_VERSION 26
#define _FILE_OFFSET_BITS 64
#import <fuse.h>

static const char* kMPQFileSystemExtendedAttributeNameC = "org.macstorm.mpqkit";
static NSString* kMPQFileSystemExtendedAttributeName = @"org.macstorm.mpqkit";

static void mpqfs_dupargs(struct fuse_args* dest, struct fuse_args* src) {
    assert(dest);
    assert(src);
    
    dest->argc = src->argc;
    dest->argv = calloc(dest->argc, sizeof(char*));
    for (int i = 0; i < dest->argc; i++) {
        if (src->argv[i]) dest->argv[i] = strdup(src->argv[i]);
    }
    dest->allocated = 1;
}


#pragma mark MPQFSTree
@interface MPQFSTree : NSObject {
    MPQFSTree* parent_;
    NSString* name_;
    NSMutableDictionary* subtrees_;
    NSMutableDictionary* attributes;
}

- (NSString*)name;

- (MPQFSTree*)subtreeForName:(NSString*)name create:(BOOL)create;
- (NSArray*)subtrees;
- (NSEnumerator*)subtreeEnumerator;

- (uint32_t)totalNodeCount;
- (MPQFSTree*)findSubtree:(NSString*)path;

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
    NSEnumerator* subtreeEnum = [subtrees_ objectEnumerator];
    MPQFSTree* subtree;
    while ((subtree = [subtreeEnum nextObject])) {
        subtree->parent_ = nil;
    }
    
    [name_ release];
    [subtrees_ release];
    [attributes release];
    
    [super dealloc];
}

- (NSString*)name {
    return name_;
}

- (MPQFSTree*)subtreeForName:(NSString*)name create:(BOOL)create {
    NSString* key = [name uppercaseString];
    
    MPQFSTree* subtree = [subtrees_ objectForKey:key];
    if (!subtree && create) {
        subtree = [MPQFSTree new];
        subtree->name_ = [name copy];
        subtree->parent_ = self;
        [subtrees_ setObject:subtree forKey:key];
        [subtree release];
    }
    
    return subtree;
}

- (NSArray*)subtrees {
    return [subtrees_ allValues];
}

- (NSEnumerator*)subtreeEnumerator {
    return [subtrees_ objectEnumerator];
}

- (void)deleteSubtreeWithName:(NSString*)name {
    NSString* key = [name uppercaseString];
    [subtrees_ removeObjectForKey:key];
}

- (uint32_t)totalNodeCount {
    uint32_t n = (uint32_t)[subtrees_ count];
    
    NSEnumerator* subtreeEnum = [subtrees_ objectEnumerator];
    MPQFSTree* subtree;
    while ((subtree = [subtreeEnum nextObject])) {
        n += [subtree totalNodeCount];
    }
    
    return n;
}

- (MPQFSTree*)findSubtreeComponents_:(NSMutableArray*)components {
    id node = nil;
    uint32_t componentCount = [components count];
    
    if ([components count] == 0) return self;
    if ([[components lastObject] length] == 0) [components removeLastObject];
    if ([components count] == 0) return self;
    if ([[components objectAtIndex:0] length] == 0) [components removeObjectAtIndex:0];
    if ([components count] == 0) return self;
    
    NSString* nodeName = [components objectAtIndex:0];
    node = [subtrees_ objectForKey:nodeName];
    if (node) {
        if (componentCount == 1) return node;
        
        [components removeObjectAtIndex:0];
        return [(MPQFSTree*)node findSubtreeComponents_:components];
    }
    
    return nil;
}

- (MPQFSTree*)findSubtree:(NSString*)path {
    NSArray* components = [[path uppercaseString] componentsSeparatedByString:@"\\"];
    return [self findSubtreeComponents_:[[components mutableCopy] autorelease]];
}

@end


#pragma mark MPQFileSystemPrivate
@interface MPQFileSystem (MPQFileSystemPrivate)
+ (MPQFileSystem*)currentFS;
@end

@implementation MPQFileSystem (MPQFileSystemPrivate)
+ (MPQFileSystem*)currentFS {
  struct fuse_context* context = fuse_get_context();
  assert(context);
  return (MPQFileSystem*)context->private_data;
}
@end


#pragma mark MPQFileSystem
@implementation MPQFileSystem

- (BOOL)buildTree_:(NSError**)error {
    archiveTree_ = [[MPQFSTree alloc] init];
    
    // Load the internal listfile
    if (![archive_ loadInternalListfile:error]) {
        if ((error && [*error code] != errHashTableEntryNotFound) || !error) return NO;
    }
    NSAutoreleasePool* p = [NSAutoreleasePool new];
#if !defined(GNUSTEP)
    NSLocale* locale = [NSLocale currentLocale];
#endif
    
    NSEnumerator* fileInfoEnumerator = [archive_ fileInfoEnumerator];
    NSDictionary* fileInfo;
    while ((fileInfo = [fileInfoEnumerator nextObject])) {
        NSString* filename = [fileInfo objectForKey:MPQFilename];
        if (!filename) continue;
        if (![[fileInfo objectForKey:MPQFileCanOpenWithoutFilename] boolValue]) continue;
        
#if !defined(GNUSTEP)
        NSLocale* file_locale = [MPQArchive localeForMPQLocale:[[fileInfo objectForKey:MPQFileLocale] unsignedShortValue]];
        if (file_locale) {
            NSString* file_locale_id = [locale displayNameForKey:NSLocaleIdentifier value:[file_locale objectForKey:NSLocaleIdentifier]];
            if (!file_locale_id) file_locale_id = [file_locale localeIdentifier];
            NSString* extension = [filename pathExtension];
            filename = [NSString stringWithFormat:@"%@ - %@%@%@", 
                [filename stringByDeletingPathExtension], file_locale_id, ([extension length] == 0) ? @"" : @".", extension];
        }
#endif
        
        MPQFSTree* current_tree = archiveTree_;
        NSArray* components = [filename componentsSeparatedByString:@"\\"];
        
        NSEnumerator* nodeEnumerator = [components objectEnumerator];
        NSString* node;
        while ((node = [nodeEnumerator nextObject])) {
            current_tree = [current_tree subtreeForName:node create:YES];
        }
        
        [current_tree setValue:[fileInfo objectForKey:MPQFileHashPosition] forKeyPath:@"attributes.position"];
    }
    
    [p release];
    ReturnValueWithNoError(YES, error)
}

- (id)initWithArchive:(MPQArchive*)archive mountPoint:(NSString*)mnt arguments:(struct fuse_args*)arguments error:(NSError**)error {
    self = [super init];
    if (!self) return nil;
    
    archive_ = [archive retain];
    mountPoint_ = [mnt retain];
    arguments_ = arguments;
    
    overwriteVolname = NO;
    
    isMounted_ = NO;
    
    if (![self buildTree_:error]) {
        [self release];
        return nil;
    }
    
#if defined(__APPLE__)
	// local to improve Finder integration, default_permissions to defer all access checks to MacFUSE, fssubtype set to Generic,
	// negative_vncache because we're RO right now, noappledouble because MPQs don't use AppleDouble.
    fuse_opt_add_arg(arguments_, "-ordonly,default_permissions,fssubtype=0,negative_vncache,noappledouble");
#else
	fuse_opt_add_arg(arguments_, "-oro,noauto_cache");
#endif
    
	// FIXME: lift the single-threaded limitation
	fuse_opt_add_arg(arguments_, "-s");
	
	// FIXME: add support for fsid option
	// FIXME: add support for iosize option
	// FIXME: use kill_on_unmount on 10.4
    
    ReturnValueWithNoError(self, error)
}

- (void)dealloc {
    [archive_ release];
    [mountPoint_ release];
    [archiveTree_ release];
    
    fuse_opt_free_args(arguments_);  
    [super dealloc];
}

- (NSString*)mountName {
    return @"MPQFS";
}

- (NSString*)mountPoint {
    return [[mountPoint_ copy] autorelease];
}

#pragma mark Initialization

- (void)fuseInit {
    isMounted_ = YES;
}

- (void)fuseDestroy {
    isMounted_ = NO;
}

#pragma mark Stat

- (int)fillStatvfsBuffer:(struct statvfs*)stbuf forPath:(NSString*)path {
    // TODO: Should we have memset the statbuf to zero, or does fuse pre-fill values?
    NSDictionary* archive_info = [archive_ archiveInfo];
    
    // Block size
    stbuf->f_bsize = stbuf->f_frsize = MPQ_BASE_SECTOR_SIZE << [[archive_info objectForKey:MPQSectorSizeShift] unsignedIntValue];
    
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

- (int)fillStatBuffer:(struct stat*)stbuf withFileInfo:(NSDictionary*)fileInfo isDirectory:(BOOL)isDirectory {
    assert(fileInfo);
    
    // Permissions (mode)
    if (isDirectory) stbuf->st_mode = S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH | S_IXUSR | S_IXGRP | S_IXOTH | S_IFDIR;
    else stbuf->st_mode = S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH | S_IFREG;
    
    // nlink
    stbuf->st_nlink = (isDirectory) ? 2 : 1;
    
    // Owner and Group
    stbuf->st_uid = geteuid();
    stbuf->st_gid = getegid();
    
    // TODO: For the timespec, there is a .tv_nsec (= nanosecond) part as well.
    // Since the NSDate returns a double, we can fill this in as well.
    
    // TODO: Fill mdate, atime, ctime from the MPQ time attribute
    NSDate* cdate = [fileInfo objectForKey:@"CreationDate"];
    
    // mtime, atime
//    if (mdate) {
//        time_t t = (time_t) [mdate timeIntervalSince1970];
//        stbuf->st_mtimespec.tv_sec = t;
//        stbuf->st_atimespec.tv_sec = t;
//    }
    
    // ctime  TODO: ctime is not "creation time" rather it's the last time the 
    // inode was changed.  mtime would probably be a closer approximation.
    if (cdate) {
#if defined(__APPLE__)
        stbuf->st_ctimespec.tv_sec = [cdate timeIntervalSince1970];
#else
        stbuf->st_ctimensec = [cdate timeIntervalSince1970];
#endif
    }
    
    // Size for regular files.
    if (!isDirectory) {
        stbuf->st_size = [[fileInfo objectForKey:MPQFileSize] unsignedIntValue];
    }
    
    // Set the number of blocks used so that Finder will display size on disk properly.
    // TODO: The stat man page says that st_blocks is "actual number of blocks allocated for the file in 512-byte units".  Investigate whether this is a man mis-print, since I suspect it should be the statvfs f_frsize? 
    if (stbuf->st_size > 0) {
        stbuf->st_blocks = stbuf->st_size / 512;
        if (stbuf->st_size % 512) {
            ++(stbuf->st_blocks);
        }
    }
    
    return 0;
}

- (int)fillStatBuffer:(struct stat*)stbuf forPath:(NSString*)path {
    MPQFSTree* node = [archiveTree_ findSubtree:[path stringByReplacingSlashWithBackslash]];
    if (!node) return -ENOENT;
    BOOL isDirectory = ([[node subtrees] count] == 0) ? NO : YES;
    
    // Get file information from the archive
    NSDictionary* fileInfo = [NSDictionary dictionary];
    if (!isDirectory) fileInfo = [archive_ fileInfoForPosition:[[node valueForKeyPath:@"attributes.position"] unsignedIntValue]];
    
    return [self fillStatBuffer:stbuf withFileInfo:fileInfo isDirectory:isDirectory];
}

#pragma mark Extended attributes

- (int)listExtendedAttributes:(NSString*)path inBuffer:(char*)buffer size:(size_t)size {
    MPQFSTree* node = [archiveTree_ findSubtree:[path stringByReplacingSlashWithBackslash]];
    if (!node) return -ENOENT;
	BOOL isDirectory = ([[node subtrees] count] == 0) ? NO : YES;
	
	if (isDirectory) return 0;
	if (buffer) strlcpy(buffer, kMPQFileSystemExtendedAttributeNameC, size);
	return strlen(kMPQFileSystemExtendedAttributeNameC) + 1;
}

- (int)getExtendedAttribute:(NSString*)path attribute:(NSString*)name buffer:(char*)buffer size:(size_t)size {
    MPQFSTree* node = [archiveTree_ findSubtree:[path stringByReplacingSlashWithBackslash]];
    if (!node) return -ENOENT;
	BOOL isDirectory = ([[node subtrees] count] == 0) ? NO : YES;
	
	memset(buffer, 0, size);
	if (isDirectory || ![name isEqualToString:kMPQFileSystemExtendedAttributeName]) return -ENOATTR;
	
	NSDictionary* fileInfo = [archive_ fileInfoForPosition:[[node valueForKeyPath:@"attributes.position"] unsignedIntValue]];
	if (![NSPropertyListSerialization propertyList:fileInfo isValidForFormat:NSPropertyListXMLFormat_v1_0]) return -EIO;
	
	NSString* error = nil;
	NSData* fileInfoXML = [NSPropertyListSerialization dataFromPropertyList:fileInfo format:NSPropertyListXMLFormat_v1_0 errorDescription:&error];
	if (!fileInfoXML) return -EIO;
	
	if (buffer) {if (size < [fileInfoXML length]) return -ERANGE; else [fileInfoXML getBytes:buffer];}
	return (int)[fileInfoXML length];
}

#pragma mark Open/Close

- (MPQFile*)openFileAtPath:(NSString*)path mode:(int)mode error:(NSError**)error {
    if (mode & (O_WRONLY | O_RDWR | O_APPEND | O_CREAT | O_TRUNC)) ReturnValueWithError(nil, NSPOSIXErrorDomain, EROFS, nil, error)
    
    MPQFSTree* node = [archiveTree_ findSubtree:[path stringByReplacingSlashWithBackslash]];
    if (!node) ReturnValueWithError(nil, NSPOSIXErrorDomain, ENOENT, nil, error)
    
    BOOL isDirectory = ([[node subtrees] count] == 0) ? NO : YES;
    if (isDirectory) ReturnValueWithError(nil, NSPOSIXErrorDomain, EISDIR, nil, error)
    
    MPQFile* file = [archive_ openFileAtPosition:[[node valueForKeyPath:@"attributes.position"] unsignedIntValue] error:(NSError**)NULL];
    if (!file) ReturnValueWithError(nil, NSPOSIXErrorDomain, ENOENT, nil, error)
    ReturnValueWithNoError(file, error)
}

- (void)releaseFileAtPath:(NSString*)path handle:(MPQFile*)handle {
    [handle release];
}

#pragma mark Reading

- (NSArray*)fullDirectoryContentsAtPath:(NSString*)path error:(NSError**)error {
    MPQFSTree* node = [archiveTree_ findSubtree:[path stringByReplacingSlashWithBackslash]];
    BOOL isDirectory = ([[node subtrees] count] == 0) ? NO : YES;
    if (!isDirectory) ReturnValueWithError(nil, NSPOSIXErrorDomain, ENOTDIR, nil, error)
    
    NSMutableArray* fullContents = [NSMutableArray array];
    [fullContents addObject:@"."];
    [fullContents addObject:@".."];
    
    NSEnumerator* subtreeEnum = [node subtreeEnumerator];
    while ((node = [subtreeEnum nextObject])) {
        [fullContents addObject:[node name]];
    }
    
    ReturnValueWithNoError(fullContents, error)
}

- (int)readFileAtPath:(NSString*)path handle:(MPQFile*)handle buffer:(char*)buffer size:(size_t)size offset:(off_t)offset {
    [handle seekToFileOffset:offset];
    ssize_t bytes_read = [handle read:buffer size:size error:(NSError**)NULL];
    if (bytes_read == -1) return -EIO;
    return bytes_read;
}

#pragma mark Writing

- (int)createDirectoryAtPath:(NSString*)path attributes:(NSDictionary*)attributes {
    return -EROFS;
}

- (int)createFileAtPath:(NSString*)path contents:(NSData*)contents attributes:(NSDictionary*)attributes {
    return -EROFS;
}

- (int)createSymbolicLinkAtPath:(NSString*)path pathContent:(NSString*)otherPath {
    return -EROFS; 
}

- (int)linkPath:(NSString*)source toPath:(NSString*)destination handler:(id)handler {
    return -EROFS; 
}

- (int)createFileAtPath:(NSString*)path attributes:(NSDictionary*)attributes {
    return -EROFS;
}

- (int)writeFileAtPath:(NSString*)path handle:(MPQFile*)handle buffer:(const char*)buffer size:(size_t)size offset:(off_t)offset {
    return -EROFS;
}

- (int)truncateFileAtPath:(NSString*)path offset:(off_t)offset {
    return -EROFS;
}

- (int)movePath:(NSString*)source toPath:(NSString*)destination handler:(id)handler {
    return -EROFS;
}

- (int)removeFileAtPath:(NSString*)path handler:(id)handler { 
    return -EROFS;
}

#pragma mark FUSE operations

static void* fusefm_init(struct fuse_conn_info* conn) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    
    MPQFileSystem* manager = [MPQFileSystem currentFS];
	[manager retain];
    [manager fuseInit];
    
    [pool release];
    return manager;
}

static void fusefm_destroy(void* private_data) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
	MPQFileSystem* manager = [MPQFileSystem currentFS];
    [manager fuseDestroy];
	[manager release];
    [pool release];
}

static int fusefm_statfs(const char* path, struct statvfs* stbuf) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    
    int res = 0;
    memset(stbuf, 0, sizeof(struct statvfs));
    
    res = [[MPQFileSystem currentFS] fillStatvfsBuffer:stbuf forPath:[NSString stringWithUTF8String:path]];
    
    [pool release];
    return res;
}

static int fusefm_getattr(const char* path, struct stat* stbuf) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    
    int res = 0;
    memset(stbuf, 0, sizeof(struct stat));
    
    res = [[MPQFileSystem currentFS] fillStatBuffer:stbuf forPath:[NSString stringWithUTF8String:path]];
    
    [pool release];
    return res;
}

static int fusefm_fgetattr(const char* path, struct stat* stbuf, struct fuse_file_info* fi) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    
	int res = 0;
    memset(stbuf, 0, sizeof(struct stat));
    
    MPQFile* file = (MPQFile*)(unsigned long)(fi->fh);
    res = [[MPQFileSystem currentFS] fillStatBuffer:stbuf withFileInfo:[file fileInfo] isDirectory:NO];
    
    [pool release];
    return res;
}

static int fusefm_readdir(const char* path, void* buf, fuse_fill_dir_t filler, off_t offset, struct fuse_file_info* fi) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    
    NSError* error = nil;
    NSArray* contents = [[MPQFileSystem currentFS] fullDirectoryContentsAtPath:[NSString stringWithUTF8String:path] error:&error];
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
    int res = [[MPQFileSystem currentFS] createFileAtPath:[NSString stringWithUTF8String:path] attributes:nil];
    [pool release];
    return res;
}

static int fusefm_unlink(const char* path) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    int ret = [[MPQFileSystem currentFS] removeFileAtPath:[NSString stringWithUTF8String:path] handler:nil];
    [pool release];
    return ret;
}

static int fusefm_rename(const char* path, const char* toPath) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    
    NSString* source = [NSString stringWithUTF8String:path];
    NSString* destination = [NSString stringWithUTF8String:toPath];
    int ret = [[MPQFileSystem currentFS] movePath:source toPath:destination handler:nil];
    
    [pool release];
    return ret;
    
}

static int fusefm_truncate(const char* path, off_t offset) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    int res = [[MPQFileSystem currentFS] truncateFileAtPath:[NSString stringWithUTF8String:path] offset:offset];
    [pool release];
    return res;
}

static int fusefm_mkdir(const char* path, mode_t mode) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    int ret = [[MPQFileSystem currentFS] createDirectoryAtPath:[NSString stringWithUTF8String:path] attributes:nil];
    [pool release];
    return ret;
}

static int fusefm_rmdir(const char* path) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    int ret = [[MPQFileSystem currentFS] removeFileAtPath:[NSString stringWithUTF8String:path] handler:nil];
    [pool release];
    return ret;
}

static int fusefm_chown(const char* path, uid_t uid, gid_t gid) {
    return -ENOSYS;
}

static int fusefm_chmod(const char* path, mode_t mode) {
    return -ENOSYS;
}

static int fusefm_open(const char* path, struct fuse_file_info* fi) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    NSError* error = nil;
    
    id object = [[MPQFileSystem currentFS] openFileAtPath:[NSString stringWithUTF8String:path] mode:fi->flags error:&error];
    if (object == nil) {
        [pool release];
        return -[error code];
    }
    fi->fh = (unsigned long)object;
    
    [pool release];
    return 0;
}

static int fusefm_release(const char* path, struct fuse_file_info* fi) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    [[MPQFileSystem currentFS] releaseFileAtPath:[NSString stringWithUTF8String:path] handle:(MPQFile*)(unsigned long)fi->fh];
    [pool release];
    return 0;
}

static int fusefm_read(const char* path, char* buf, size_t size, off_t offset, struct fuse_file_info* fi) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    int length = [[MPQFileSystem currentFS] readFileAtPath:[NSString stringWithUTF8String:path] handle:(MPQFile*)(unsigned long)fi->fh buffer:buf size:size offset:offset];
	[pool release];
    return length;
}

static int fusefm_write(const char* path, const char* buf, size_t size, off_t offset, struct fuse_file_info* fi) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    int length = [[MPQFileSystem currentFS] writeFileAtPath:[NSString stringWithUTF8String:path] handle:(id)(unsigned long)fi->fh buffer:buf size:size offset:offset];
    [pool release];
    return length;
}

static int fusefm_ftruncate(const char* path, off_t offset, struct fuse_file_info* fh) {
    return fusefm_truncate(path, offset);
}

static int fusefm_setxattr(const char* path, const char* attribute, const char* value, size_t size, int flags) {
	return -EROFS;
}

static int fusefm_getxattr(const char* path, const char* attribute, char* value, size_t size) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
	int length = [[MPQFileSystem currentFS] getExtendedAttribute:[NSString stringWithUTF8String:path] attribute:[NSString stringWithUTF8String:attribute] buffer:value size:size];
	[pool release];
    return length;
}

static int fusefm_listxattr(const char* path, char* list, size_t size) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    int length = [[MPQFileSystem currentFS] listExtendedAttributes:[NSString stringWithUTF8String:path] inBuffer:list size:size];
    [pool release];
    return length;
}

static int fusefm_removexattr(const char* path, const char* attribute) {
	return -EROFS;
}

static int fusefm_readlink(const char* path, char* buf, size_t size) {
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
	//.access = fusefm_access,
    .chown = fusefm_chown,
    .chmod = fusefm_chmod,
    
    // File operations
    .open = fusefm_open,
    .release = fusefm_release,
    .read = fusefm_read,
    .write = fusefm_write,
    .ftruncate = fusefm_ftruncate,
	
	// Extended attributes
	.setxattr = fusefm_setxattr,
	.getxattr = fusefm_getxattr,
	.listxattr = fusefm_listxattr,
	.removexattr = fusefm_removexattr,
    
    // Links
    .readlink = fusefm_readlink,
};

#pragma mark Mount

- (void)startFuse {
    struct fuse_args args;
    mpqfs_dupargs(&args, arguments_);
    
#if defined(__APPLE__)
    if (overwriteVolname) {
		const char* flub = [[NSString stringWithFormat:@"-ovolname=%@", [[archive_ path] lastPathComponent]] UTF8String];
		fuse_opt_add_arg(&args, flub);
	}
#endif
    
    fuse_main(args.argc, args.argv, &fusefm_operations, self);
    fuse_opt_free_args(arguments_);
}

@end
