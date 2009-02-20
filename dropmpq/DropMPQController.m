#import <Cocoa/Cocoa.h>

#import <MPQKit/MPQKit.h>
#import <Sparkle/SUUpdater.h>

#import "DropMPQController.h"
#import "MVPreferencesController.h"
#import "PreferenceKeys.h"

#define NSInt(a) ([NSNumber numberWithInt:a])
#define NSYes ([NSNumber numberWithBool:YES])
#define NSNo ([NSNumber numberWithBool:NO])

@implementation DropMPQController

static NSString *modeTaskStrings [] = {@"", @"Preserving the old archive", @"Processing content...", @"Writing the archive..."};
static NSString *modeInfoStrings [] = {@"", @"Exporting \n%@", @"", @"%@"};

#define kIdleMode 		0
#define kPreserveMode 	1
#define kProcessMode 	2
#define kSaveMode 		3

#pragma mark class init methods

- (id)init {
    self = [super init];
	if (!self) return nil;
	
	NSDictionary *regDict = [NSDictionary dictionaryWithObjectsAndKeys:
		[NSDictionary dictionaryWithObjectsAndKeys:
			NSInt(1), PRESERVE_ARCHIVE_KEY,
			NSInt(0), MAKE_IMP_KEY,
			[NSDictionary dictionaryWithObjectsAndKeys:
				NSInt(MPQFileCompressed), MPQFileFlags,
				NSInt(MPQZLIBCompression), MPQCompressor,
				NSInt(9), MPQCompressionQuality,
				NSInt(MPQNeutral), MPQFileLocale,
				NSYes, MPQOverwrite,
				nil], DEFAULT_IMPORT_DICT_KEY,
			[NSDictionary dictionaryWithObjectsAndKeys:
				NSInt(0), MPQCompressor,
				NSInt(0), MPQCompressionQuality,
				NSInt(MPQNeutral), MPQFileLocale,
				NSYes, MPQOverwrite,
				nil], @"mp3",
			[NSDictionary dictionaryWithObjectsAndKeys:
				NSInt(0), MPQCompressor,
				NSInt(0), MPQCompressionQuality,
				NSInt(MPQNeutral), MPQFileLocale,
				NSYes, MPQOverwrite,
				nil], @"aac",
			[NSDictionary dictionaryWithObjectsAndKeys:
				NSInt(0), MPQCompressor,
				NSInt(0), MPQCompressionQuality,
				NSInt(MPQNeutral), MPQFileLocale,
				NSYes, MPQOverwrite,
				nil], @"ogg",
			[NSDictionary dictionaryWithObjectsAndKeys:
				NSInt(0), MPQCompressor,
				NSInt(0), MPQCompressionQuality,
				NSInt(MPQNeutral), MPQFileLocale,
				NSYes, MPQOverwrite,
				nil], @"mp4",
			[NSDictionary dictionaryWithObjectsAndKeys:
				NSInt(0), MPQCompressor,
				NSInt(0), MPQCompressionQuality,
				NSInt(MPQNeutral), MPQFileLocale,
				NSYes, MPQOverwrite,
				nil], @"mov",
			[NSDictionary dictionaryWithObjectsAndKeys:
				NSInt(0), MPQCompressor,
				NSInt(0), MPQCompressionQuality,
				NSInt(MPQNeutral), MPQFileLocale,
				NSYes, MPQOverwrite,
				nil], @"w3m",
			[NSDictionary dictionaryWithObjectsAndKeys:
				NSInt(0), MPQCompressor,
				NSInt(0), MPQCompressionQuality,
				NSInt(MPQNeutral), MPQFileLocale,
				NSYes, MPQOverwrite,
				nil], @"w3x",
			[NSDictionary dictionaryWithObjectsAndKeys:
				NSInt(MPQFileCompressed), MPQFileFlags,
				NSInt((MPQStereoADPCMCompression | MPQHuffmanTreeCompression)), MPQCompressor,
				NSInt(MPQADPCMQualityHigh), MPQCompressionQuality,
				NSInt(MPQNeutral), MPQFileLocale,
				NSYes, MPQOverwrite,
				nil], @"wav",
			[NSDictionary dictionaryWithObjectsAndKeys:
				NSInt(0), MPQCompressor,
				NSInt(0), MPQCompressionQuality,
				NSInt(MPQNeutral), MPQFileLocale,
				NSYes, MPQOverwrite,
				nil], @"smk",
			nil], DEFAULT_IMPORT_DICT_PREF,
		nil];

	[[NSUserDefaults standardUserDefaults] registerDefaults:regDict];
	
	// search for any invalid import dictionary based on the presence of the old keys
	NSEnumerator* importDictEnum = [[[NSUserDefaults standardUserDefaults] objectForKey:DEFAULT_IMPORT_DICT_PREF] objectEnumerator];
	NSDictionary* importDict;
	id doMe;
	while ((importDict = [importDictEnum nextObject])) {
		if ([importDict isKindOfClass:[NSDictionary class]] == NO) continue;
		
		doMe = [importDict objectForKey:@"Compressor"];
		if (doMe) break;
		doMe = [importDict objectForKey:@"Flags"];
		if (doMe) break;
		doMe = [importDict objectForKey:@"Locale"];
		if (doMe) break;
		doMe = [importDict objectForKey:@"Quality"];
		if (doMe) break;
	}
	
	if (doMe) {
		_blewPrefsAway = YES;
		NSEnumerator* keyEnum = [regDict keyEnumerator];
		id key;
		while ((key = [keyEnum nextObject])) [[NSUserDefaults standardUserDefaults] setObject:[regDict objectForKey:key] forKey:key];
	}
    
    return self;
}

- (void)awakeFromNib {
    m_displayMode = kIdleMode;
    
	// Setup the progress bar
	[m_progress setHidden:YES];
	[m_progress setMaxValue:1.0];
	[m_progress stopAnimation:self];
	[m_progress setIndeterminate:NO];
	[m_progress setUsesThreadedAnimation:YES];
	
	isAnimating = NO;
	isIdle = YES;
}

- (id <SUVersionComparison>)versionComparatorForUpdater:(SUUpdater*)updater {
	return comparator;
}

#pragma mark app delegate methods

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
    // Prepare a few things
    m_foldersToProcess = [[NSMutableArray alloc] initWithCapacity:0x10];
    m_isRunning = YES;
    m_isProcessing = NO;
    
    // Prepare the locks
    m_dataLock = [[NSConditionLock alloc] initWithCondition:NO_ITEM];
	
	// Launch the worker thread
    [NSThread detachNewThreadSelector:@selector(processFolderThread:) toTarget:self withObject:nil];
	
	// Start the UI update timer
	ui_tick = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updateUI:) userInfo:nil repeats:YES];
	
	// check if we blew the preferences
	if (_blewPrefsAway) {
		NSAlert* alert = [NSAlert alertWithMessageText:@"All prefrences have been reset because the format has changed significantly since the previous release of DropMPQ." 
										 defaultButton:@"OK" 
									   alternateButton:@"Open preferences..." 
										   otherButton:nil 
							 informativeTextWithFormat:@"Default values have been set for all preferences. You may review those defaults now, or simply use DropMPQ and check them at your convenience."];
		NSInteger result = [alert runModal];
		if (result == NSAlertAlternateReturn) [self displayPreferences:self];
	}
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (m_isProcessing) return NSTerminateCancel;
    else return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    m_isRunning = FALSE;
    [m_foldersToProcess release];
    [m_dataLock release];
	
	[ui_tick invalidate];
	ui_tick = nil;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication {
    return YES;
}

- (BOOL)application:(NSApplication *)theApplication openFile:(NSString *)filename {
	[self filesDropped:[NSArray arrayWithObject:filename]];
	return YES;
}

#pragma mark window delegate methods

- (BOOL)windowShouldClose:(id)sender {
    return !m_isProcessing;
}

#pragma mark action methods

- (IBAction)displayPreferences:(id)sender {

}

- (IBAction)openDocument:(id)sender {
    // Let's select a folder!

    // First we setup our dialog
    NSOpenPanel * chooseDirPanel = [NSOpenPanel openPanel];
    [chooseDirPanel setCanChooseFiles:NO];
    [chooseDirPanel setCanChooseDirectories:YES];
    [chooseDirPanel setAllowsMultipleSelection:NO];

    int returnCode = [chooseDirPanel runModalForTypes:nil];
    if (returnCode == NSOKButton) [self filesDropped:[chooseDirPanel filenames]];
}

#pragma mark file drop view delegate methods

- (BOOL)fileIsValidForDrop:(NSString *)path {
    if (m_isProcessing) return NO;
    
    BOOL isDir = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir) return YES;
        
    return NO;
}

- (void)filesDropped:(NSArray *)items {
    if (!items || ![items count]) return;

    // We are in business
    [m_dataLock lock];
    [m_foldersToProcess addObjectsFromArray:items];
    [m_dataLock unlockWithCondition:HAS_ITEM];
}

#pragma mark worker thread methods

- (void)processFolderThread:(id)object {
    // This will be a thread, so we need our own autorelease pool
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
    BOOL isDir = FALSE;
    NSFileManager *dfm = [[NSFileManager defaultManager] retain];
	
	NSString *old_string = nil;
    NSError *error = nil;
	
    // We need to retain the lock objects
    [m_dataLock retain];
	
    // We enter the thread loop
    while (m_isRunning) {
        // create an autorelease pool to collect temporary objects
        // recreate it here to free up memory
        [pool release];
        pool = [[NSAutoreleasePool alloc] init];
        
        m_isProcessing = NO;
        
        // reset variables to idle state
		old_string = m_infoString;
		m_infoString = [@"" retain];
        [old_string release];
		old_string = nil;
		
        m_displayMode = kIdleMode;
        
		// Block until we have something to process
        [m_dataLock lockWhenCondition:HAS_ITEM];
        
		// Get the first item to process
        NSString *path = [[NSString alloc] initWithString:[m_foldersToProcess objectAtIndex:0]];
		
        // Don't touch the array while it is being edited
        [m_foldersToProcess removeObjectAtIndex:0];
        if ([m_foldersToProcess count]) [m_dataLock unlockWithCondition:HAS_ITEM];
        else [m_dataLock unlockWithCondition:NO_ITEM];
		
        // start the barber pole spinning - this may take a bit
        m_isProcessing = YES;
        
        // Check if there is a mpq.plist file in the target folder
        NSDictionary *attribDict = [[NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"mpq.plist"]] retain];
        NSDictionary *prefAttribDict = [[[NSUserDefaults standardUserDefaults] objectForKey:DEFAULT_IMPORT_DICT_PREF] retain];
        if (!attribDict) attribDict = [prefAttribDict retain];
        
		// Load the default import dictionary
        NSDictionary *defaultImportDict = [attribDict objectForKey:DEFAULT_IMPORT_DICT_KEY];
        if (!defaultImportDict) defaultImportDict = [prefAttribDict objectForKey:DEFAULT_IMPORT_DICT_KEY];
		
        // Alias the default dictionary
        NSDictionary *importDict = [defaultImportDict retain];
		
		// Some variables we'll need
		MPQArchive *archive = nil;
        NSMutableArray *excludeList = [[NSMutableArray arrayWithCapacity:0x20] retain];
        
        NSNumber *temp = nil;
        BOOL bPreserveArchive = YES;
        BOOL bMakeImp = YES;
        
		// Do we preserve an existing archive?
        temp = [attribDict objectForKey:PRESERVE_ARCHIVE_KEY];
        if (!temp) temp = [prefAttribDict objectForKey:PRESERVE_ARCHIVE_KEY];
        bPreserveArchive = [temp boolValue];
        
		// Do we generate a Warcraft III import key?
        temp = [attribDict objectForKey:MAKE_IMP_KEY];
        if (!temp) temp = [prefAttribDict objectForKey:MAKE_IMP_KEY];
        bMakeImp = [temp boolValue];
        
        // Grab an NSArray out of the enumerator, cause it's gonna be more conveniant that way
        NSArray *folderContent = [[[dfm enumeratorAtPath:path] allObjects] retain];
        
        NSString *archivePath = [[path stringByAppendingPathExtension:@"mpq"] retain];
        if (bPreserveArchive && [dfm fileExistsAtPath:archivePath]) archive = [[MPQArchive archiveWithPath:archivePath] retain];    
        else archive = [[MPQArchive archiveWithFileLimit:[folderContent count]] retain];
        if (!archive) {
            [attribDict release];
            [prefAttribDict release];
            [defaultImportDict release];
            [path release];
            [folderContent release];
            [excludeList release];
            continue;
        }
        
		// Prepare for UI updates
		m_fTotal = [folderContent count];
        m_fLeft = m_fTotal;
        m_displayMode = kProcessMode;
        
        // Set ourselves as the delegate so we get the willAddFile messages
        [archive setDelegate:self];
        
        // Load listfile of the archive so that we maintain it's current content, if any
        [archive loadInternalListfile:NULL];
        
        // We are ready to loop through the files
        NSString *itemSubPath = nil;
        NSString *importPath = nil;
        unsigned i = 0;
        BOOL bFileExists = NO;
        
		// Track imported files for the IMP generation
        NSMutableArray *importList = (bMakeImp) ? [[NSMutableArray arrayWithCapacity:m_fTotal] retain] : nil;
        for (i = 0; i < [folderContent count]; i++) {
            // create an autorelease pool to collect temporary objects
            // this is another long loop so flush the pool here too
            [pool release];
            pool = [[NSAutoreleasePool alloc] init];
            
            // Speed cache
			itemSubPath = [folderContent objectAtIndex:i];
            bFileExists = [dfm fileExistsAtPath:[path stringByAppendingPathComponent:itemSubPath] isDirectory:&isDir];
			
			// One less file to process
			m_fLeft--;
			
            // We need to make sure the current item is NOT a folder
            if (!bFileExists || isDir) continue;
			
            // If the file name starts with a period, we don't import
            // TODO: this should be a preference setting
            if ([[[itemSubPath lastPathComponent] substringToIndex:1] isEqualToString:@"."]) continue;
            
			// Compute the import path
            importPath = [path stringByAppendingPathComponent:itemSubPath];
            itemSubPath = [itemSubPath stringByReplacingSlashWithBackslash];
            
			// Check if we have a special rule for this kind of file. If not, use the default import dictionary
            importDict = [attribDict objectForKey:[importPath pathExtension]];
            if (!importDict) importDict = defaultImportDict;
			
			// If this file isn't in the IMP exlude list, add it to the IMP import list
            [importList addObject:itemSubPath];
            
            // Add the file to the archive
            if (![archive addFileWithPath:importPath filename:itemSubPath parameters:importDict error:&error])
				NSLog(@"failed to import %@: %@", itemSubPath, error);
            importDict = nil;
        }
        
        [pool release];
        pool = [[NSAutoreleasePool alloc] init];
        
        if (bMakeImp) {
            // make a war3x war3campaign.imp file
            NSMutableData *impData = [NSMutableData dataWithLength:8];
            
            NSData *impOldData = [archive copyDataForFile:@"war3campaign.imp" locale:MPQNeutral];
            if (impOldData) {
                [impData setData:impOldData];
				[impOldData release];
				impOldData = nil;
			}
            
            *(unsigned long*)[impData mutableBytes] = CFSwapInt32(1);
            unsigned long numFiles = CFSwapInt32(*(((unsigned long*)[impData mutableBytes])+1)) + [importList count];
            *(((unsigned long*)[impData mutableBytes])+1) = CFSwapInt32(numFiles);
            
            NSEnumerator *importEnum = [importList objectEnumerator];
            NSString *aFile;
            const char flagValue = 0xD;
            while ((aFile = [importEnum nextObject])) {
                [impData appendBytes:&flagValue length:1];
				NSData* aFileData = [aFile dataUsingEncoding:NSUTF8StringEncoding];
                [impData appendBytes:[aFileData bytes] length:[aFileData length]];
				[impData appendBytes:"\0" length:1];
            }
            
            [archive addFileWithData:impData filename:@"war3campaign.imp" parameters:defaultImportDict];
        }
        
        [importList release];
        importList = nil;
        
        [excludeList release];
        excludeList = nil;
        
		m_fTotal = [archive operationCount];
		m_fLeft = m_fTotal;
        m_displayMode = kSaveMode;
        
        if (![archive writeToFile:archivePath atomically:YES error:&error]) {
			NSBeep();
            [NSApp presentError:error];
		}
        
		// Clean up
        [archive release];
        archive = nil;
		
        [attribDict release];
        attribDict = nil;
        
        [prefAttribDict release];
        prefAttribDict = nil;
        
        [defaultImportDict release];
        defaultImportDict = nil;
		
        [archivePath release];
        archivePath = nil;
        
        [path release];
        path = nil;
		
        [folderContent release];
        folderContent = nil;
    }
	
    // We clean up
    [m_dataLock release];
    [dfm release];
    [pool release];
}

- (void)archive:(MPQArchive *)archive willAddFile:(NSString *)file {
    NSString *old_string = m_infoString;
	m_infoString = [file retain];
	[old_string release];
	
	m_fLeft--;
}

- (void)archive:(MPQArchive*)archive failedToAddFile:(NSString*)filename error:(NSError*)error {
	NSLog(@"FAILED TO ADD %@: %@", filename, error);
}

#pragma mark UI update methods

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem {
    if (m_isProcessing) {
        SEL action = [anItem action];
        if (action == @selector(openDocument:)) return NO;
    }
    
    return YES;
}

- (void)updateUI:(id)anObject {
	[m_taskField setStringValue:modeTaskStrings[m_displayMode]];
    [m_taskInfoField setStringValue:[NSString stringWithFormat:modeInfoStrings[m_displayMode], m_infoString]];
    
    if (m_displayMode == kIdleMode && !isIdle) {
		isIdle = YES;
		
		[m_progress setHidden:YES];
		[m_progress setMaxValue:1.0];
		[m_progress stopAnimation:self];
		[m_progress setIndeterminate:NO];
	} else if (m_displayMode != kIdleMode) {
		if (isIdle) {
			isIdle = NO;
			[m_progress setHidden:NO];
		}
		
		if (m_fLeft == -1) {
			if (!isAnimating) {
				isAnimating = YES;
				[m_progress setIndeterminate:YES];
				[m_progress startAnimation:self];
			}
		} else {
			if (isAnimating) {
				isAnimating = NO;
				[m_progress stopAnimation:self];
				[m_progress setIndeterminate:NO];
			}
			
			[m_progress setDoubleValue:(m_fLeft <= 0.0) ? 1.0 : 1 - (m_fLeft / m_fTotal)];
		}
	}
}

@end
