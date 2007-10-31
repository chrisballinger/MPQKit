//
//  mpqfsd.m
//  MPQKit
//
//  Created by Jean-Francois Roy on 26/03/2007.
//  Copyright MacStorm 2007. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <unistd.h>

#import "MPQFileSystem.h"

#define FUSE_USE_VERSION 26
#define _FILE_OFFSET_BITS 64
#import <fuse.h>

static NSString *archive_path = nil;
static NSMutableArray *listfiles = nil;
static NSString *mount_point = nil;

static BOOL has_volname = NO;

enum {
    KEY_LISTFILE,
    KEY_HELP,
    KEY_VERSION,
};

#define MPQFS_OPT(t, p, v) { t, offsetof(struct sshfs, p), v }
static struct fuse_opt mpqfs_opts[] = {
    FUSE_OPT_KEY("-l ",         KEY_LISTFILE),
    FUSE_OPT_KEY("--listfile=", KEY_LISTFILE),
    FUSE_OPT_KEY("--version",   KEY_VERSION),
    FUSE_OPT_KEY("-h",          KEY_HELP),
    FUSE_OPT_KEY("--help",      KEY_HELP),
    FUSE_OPT_END
};

static void usage(const char *program) {
    fprintf(stderr, 
"usage: %s archive mountpoint [options]\n"
"\n"
"general options:\n"
"    -o opt,[opt...]        mount options\n"
"    -h   --help            print help\n"
"    -V   --version         print version\n"
"\n"
"MPQFS options:\n"
"    -l   --listfile        supply an external listfile to MPQFS\n"
"\n", program);
}

static struct fuse_operations dummy_opts;

static int mpqfs_opt_proc(void *data, const char *arg, int key, struct fuse_args *outargs) {
    NSString *listfile = nil;
    switch (key) {
        case FUSE_OPT_KEY_OPT:
            if (strstr(arg, "volname") != NULL) {
                has_volname = YES;
            }
            return 1;
            
        case FUSE_OPT_KEY_NONOPT:
            if (!archive_path) {
                archive_path = [[NSString alloc] initWithCString:arg encoding:NSUTF8StringEncoding];
                return 0;
            }
            if (!mount_point) {
                mount_point = [[NSString alloc] initWithCString:arg encoding:NSUTF8StringEncoding];
                return 1;
            }
            return 1;
        
        case KEY_LISTFILE:
            if (strstr(arg, "-l") == arg) listfile = [[NSString stringWithCString:arg + 2 encoding:NSUTF8StringEncoding] stringByStandardizingPath];
            if (strstr(arg, "--listfile=") == arg) listfile = [[NSString stringWithCString:arg + 11 encoding:NSUTF8StringEncoding] stringByStandardizingPath];
            [listfiles addObject:listfile];
            return 0;
        
        case KEY_HELP:
            usage(outargs->argv[0]);
            fuse_opt_add_arg(outargs, "-ho");
            fuse_main(outargs->argc, outargs->argv, &dummy_opts, NULL);
            exit(1);
            
        case KEY_VERSION:
            fprintf(stderr, "MPQFS version %s\n", "0.3.1");
            fuse_opt_add_arg(outargs, "--version");
            fuse_main(outargs->argc, outargs->argv, &dummy_opts, NULL);
            exit(0);
            
        default:
            fprintf(stderr, "internal error\n");
            abort();
    }
}

int main(int argc, char *argv[]) {
    NSAutoreleasePool *p = [NSAutoreleasePool new];
    NSError *error = nil;
    
    struct fuse_args args = FUSE_ARGS_INIT(argc, argv);
    listfiles = [[NSMutableArray alloc] init];
    
    if (fuse_opt_parse(&args, NULL, mpqfs_opts, mpqfs_opt_proc) == -1) exit(1);
    
    if (archive_path == nil) {
        fprintf(stderr, "missing archive path\n");
        fprintf(stderr, "see `%s -h' for usage\n", argv[0]);
        goto Exit1;
    }
    
    if (mount_point == nil) {
        fprintf(stderr, "missing mount point\n");
        fprintf(stderr, "see `%s -h' for usage\n", argv[0]);
        goto Exit1;
    }
    
    MPQArchive *archive = [[MPQArchive alloc] initWithPath:archive_path error:&error];
    if (!archive) {
        fprintf(stderr, "error opening archive: %s\n", [[error description] UTF8String]);
        fprintf(stderr, "see `%s -h' for usage\n", argv[0]);
        goto Exit1;
    }
    [archive_path release];
    
    if ([listfiles count] > 0) {
        NSEnumerator *listfileEnum = [listfiles objectEnumerator];
        NSString *listfile;
        while ((listfile = [listfileEnum nextObject])) {
            [archive addContentsOfFileToFileList:listfile];
        }
    }
    [listfiles release];
    
    MPQFileSystem *fs = [[MPQFileSystem alloc] initWithArchive:archive mountPoint:mount_point arguments:&args error:&error];
    if (!fs) {
        fprintf(stderr, "error creating MPQ filesystem: %s\n", [[error description] UTF8String]);
        [archive release];
        goto Exit1;
    }
    [archive release];
    [mount_point release];
    
    // Set options
    [fs setValue:[NSNumber numberWithBool:(has_volname) ? NO : YES] forKey:@"overwriteVolname"];
    
    // Start fuse (does not return until unmount)
    [fs startFuse];
    
    [fs release];
    [p release];
    return 0;

Exit1:
    fuse_opt_free_args(&args);
    [p release];
    exit(1);
}
