//
//  MPQFSApplicationDelegate.m
//  MPQKit
//
//  Created by Jean-François Roy on 31/03/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#import "MPQFSApplicationDelegate.h"


@implementation MPQFSApplicationDelegate

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

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename {
    [NSTask launchedTaskWithLaunchPath:[[NSBundle mainBundle] pathForAuxiliaryExecutable:@"mpqfsd"] 
        arguments:[NSArray arrayWithObjects:filename, [self mountPointForArchivePath_:filename], nil]];
    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:filename]];
    return YES;
}

- (IBAction)openDocument:(id)sender {
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseFiles:YES];
    [openPanel setCanChooseDirectories:NO];
    [openPanel setAllowsMultipleSelection:NO];
	
    int returnCode = [openPanel runModalForTypes:[NSArray arrayWithObject:@"mpq"]];
    if(returnCode == NSOKButton) [self application:NSApp openFile:[openPanel filename]];
}

@end
