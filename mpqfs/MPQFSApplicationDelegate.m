//
//  MPQFSApplicationDelegate.m
//  MPQKit
//
//  Created by Jean-François Roy on 31/03/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#import "MPQFSApplicationDelegate.h"


@implementation MPQFSApplicationDelegate

- (NSArray *)standardListfileArguments_ {
    NSString *listfileDirectory = [[NSBundle mainBundle] pathForResource:@"listfiles" ofType:@""];
    if (!listfileDirectory) return [NSArray array];
    
    NSArray *listfileDirectoryContent = [[NSFileManager defaultManager] directoryContentsAtPath:listfileDirectory];
    NSMutableArray *arguments = [NSMutableArray arrayWithCapacity:[listfileDirectoryContent count]];
    
    NSEnumerator *directoryContentEnum = [listfileDirectoryContent objectEnumerator];
    NSString *listfile;
    while ((listfile = [directoryContentEnum nextObject])) {
        [arguments addObject:[NSString stringWithFormat:@"--listfile=%@", [listfileDirectory stringByAppendingPathComponent:listfile]]];
    }
    
    return arguments;
}

- (NSString *)mountPointForArchivePath_:(NSString *)path {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *basePoint = [@"/Volumes" stringByAppendingPathComponent:[path lastPathComponent]];
    
    NSString *mountPoint = [NSString stringWithString:basePoint];
    uint32_t count = 1;
    while ([manager fileExistsAtPath:mountPoint]) {
        mountPoint = [basePoint stringByAppendingFormat:@" - %u", count++];
    }
    
    [manager createDirectoryAtPath:mountPoint attributes:nil];
    return mountPoint;
}

- (BOOL)mountArchive_:(NSString *)path loadingListfiles:(BOOL)loadListfiles {
    NSMutableArray *arguments = [NSMutableArray arrayWithObjects:path, [self mountPointForArchivePath_:path], nil];
    if (loadListfiles) [arguments addObjectsFromArray:[self standardListfileArguments_]];
    // FIXME: add support for volicon
	
#if defined(__APPLE__)
    [NSTask launchedTaskWithLaunchPath:[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"mpqfsd"] arguments:arguments];
#else
    [NSTask launchedTaskWithLaunchPath:@"mpqfsd" arguments:arguments];
#endif
    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:path]];
    return YES;
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename {
    return [self mountArchive_:filename loadingListfiles:NO];
}

- (IBAction)openDocument:(id)sender {
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseFiles:YES];
    [openPanel setCanChooseDirectories:NO];
    [openPanel setAllowsMultipleSelection:NO];
    [openPanel setAccessoryView:loadStdListfilesView];
	
#if defined(__APPLE__)
    int returnCode = [openPanel runModalForTypes:
        [NSArray arrayWithObjects:@"mpq", NSFileTypeForHFSTypeCode('D2pq'), NSFileTypeForHFSTypeCode('W!pq'), NSFileTypeForHFSTypeCode('MPQA'), NSFileTypeForHFSTypeCode('Smpq'), nil]];
#else
    int returnCode = [openPanel runModalForTypes:
        [NSArray arrayWithObjects:@"mpq", @"MPQ", nil]];
#endif
    if (returnCode == NSOKButton) [self mountArchive_:[openPanel filename] loadingListfiles:([loadStdListfilesButton state] == NSOnState) ? YES : NO];
}

@end
