//
//  importPref.m
//  importPref
//
//  Created by BahamutZERO on Sat May 17 2003.
//  Copyright (c) 2003 MacStorm. All rights reserved.
//

#import "DQImportPreferences.h"
#import "PreferenceKeys.h"

#import <MPQKit/MPQKit.h>

#define NSPrefLocalizedString(key, comment) [[self bundle] localizedStringForKey:(key) value:@"" table:nil]
#define NSInt(a) ([NSNumber numberWithInt:a])
#define min(a, b) ((a) < (b) ? (a) : (b))

@implementation DQImportPreferences

- (id)initWithBundle:(NSBundle *)bundle {
    self = [super init];
    if (!self)
		return nil;
        
    m_typeKeysArray = [[NSMutableArray alloc] initWithCapacity:0x10];
    m_typeValuesArray = [[NSMutableArray alloc] initWithCapacity:0x10];
    m_isEditing = NO;
    m_madeNewEntry = NO;
    m_newCount = 0;
    
    return self;
}

- (void)dealloc {
    [m_typeKeysArray release];
    [m_typeValuesArray release];
	[super dealloc];
}

- (void)awakeFromNib {
    Class imageAndTextCellClass = nil;
    id imageAndTextCell = nil;
    if ((imageAndTextCellClass = [[NSBundle mainBundle] classNamed:@"ImageAndTextCell"])) {
        imageAndTextCell = [[[imageAndTextCellClass alloc] init] autorelease];
        [imageAndTextCell setEditable:YES];
        if (!imageAndTextCell)
			NSLog(@"Could not get the imageAndTextCell class");
    
        NSTableColumn *tableColumn = [m_typeTable tableColumnWithIdentifier:@"filetype"];
        if (!tableColumn)
			NSLog(@"Could not get the filetype column");
        
        [tableColumn setDataCell:imageAndTextCell];
        [tableColumn setEditable:YES];
        
        [m_typeTable setIntercellSpacing:NSMakeSize(3.0, 32.0)];
    }
}

- (void)mainViewDidLoad {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSDictionary *defaultImportDict = [prefs objectForKey:DEFAULT_IMPORT_DICT_PREF];
    NSDictionary *importDict = [defaultImportDict objectForKey:DEFAULT_IMPORT_DICT_KEY];
    
    int flags = [[importDict objectForKey:MPQFileFlags] intValue];
    int compressor = [[importDict objectForKey:MPQCompressor] intValue];
    
    if ((flags & MPQFileDiabloCompressed)) {
        compressor = MPQPKWARECompression;
        [m_compressorMenu setEnabled:NO];
    } else [m_compressorMenu setEnabled:YES];
    
    id compMenuItem = [[m_compressorMenu menu] itemWithTag:compressor];
    if (compMenuItem)
		[m_compressorMenu selectItem:compMenuItem];
    else {
        compressor = MPQZLIBCompression;
        flags &= ~MPQFileDiabloCompressed;
        
        compMenuItem = [[m_compressorMenu menu] itemWithTag:compressor];
        NSAssert(compMenuItem != nil, @"compMenuItem was nil for MPQZLIBCompression");
        [m_compressorMenu selectItem:compMenuItem];
    }

    [m_encryptFileCheckbox setState:(flags & MPQFileEncrypted) ? YES : NO];
    [m_offsetKeyCheckbox setState:(flags & MPQFileOffsetAdjustedKey) ? YES : NO];
    [m_diabloCompCheckbox setState:(flags & MPQFileDiabloCompressed) ? YES : NO];
    [m_replaceCheckbox setState:[[importDict objectForKey:MPQOverwrite] boolValue]];
    
    if (compressor == MPQZLIBCompression) {
        [m_compressionLevelMenu setMenu:m_zlibQualityMenu];
        [m_compressionLevelMenu setEnabled:YES];
    } else if (compressor == MPQBZIP2Compression) {
        [m_compressionLevelMenu setMenu:m_bzip2QualityMenu];
        [m_compressionLevelMenu setEnabled:YES];
    } else {
        [m_compressionLevelMenu selectItem:nil];
        [m_compressionLevelMenu setEnabled:NO];
    }

    int quality = [[importDict objectForKey:MPQCompressionQuality] intValue];
    NSMenuItem *compQualMenuItem;
    if (compressor == MPQZLIBCompression || compressor == MPQBZIP2Compression) {
        compQualMenuItem = [[m_compressionLevelMenu menu] itemWithTag:quality];
        if (compQualMenuItem)
			[m_compressionLevelMenu selectItem:compQualMenuItem];
        else {
            quality = 9;
            compQualMenuItem = [[m_compressionLevelMenu menu] itemWithTag:quality];
            NSAssert(compMenuItem != nil, @"compQualMenuItem was nil for the default compression quality of the selected compressor");
            [m_compressionLevelMenu selectItem:compQualMenuItem];
        }
    }
    
    [m_typeKeysArray removeAllObjects];
    [m_typeValuesArray removeAllObjects];
    
    NSEnumerator *keyEnum = [defaultImportDict keyEnumerator];
    NSString *aKey;
    while ((aKey = [keyEnum nextObject])) {
        if ([aKey isEqualToString:PRESERVE_ARCHIVE_KEY] || [aKey isEqualToString:MAKE_IMP_KEY] || [aKey isEqualToString:DEFAULT_IMPORT_DICT_KEY])
			continue;
        [m_typeKeysArray addObject:aKey];
    }
    
    [m_typeKeysArray sortUsingSelector:@selector(compare:)];
    unsigned i = 0;
    for (; i < [m_typeKeysArray count]; i++)
		[m_typeValuesArray addObject:[defaultImportDict objectForKey:[m_typeKeysArray objectAtIndex:i]]];
    
    [m_typeTable reloadData];
    [m_typeTable selectRow:0 byExtendingSelection:NO];
}

- (BOOL)shouldUnselect {
    if (m_isEditing)
		NSBeep();
    return (m_isEditing) ? NO : YES;
}

- (BOOL)tabView:(NSTabView *)tabView shouldSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    if ([tabView indexOfTabViewItem:tabViewItem] == 0) {
        if (m_isEditing)
			NSBeep();
        return
			!m_isEditing;
    } else return YES;
}

- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    [[tabView window] makeFirstResponder:[tabViewItem initialFirstResponder]];
}

- (IBAction)savePreferencesAction:(id)sender {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    
    int flags = 0;
    if ([m_encryptFileCheckbox state])
		flags |= MPQFileEncrypted;
    if ([m_offsetKeyCheckbox state])
		flags |= MPQFileOffsetAdjustedKey;
    if ([m_diabloCompCheckbox state])
		flags |= MPQFileDiabloCompressed;
    
    int compressor = [[m_compressorMenu selectedItem] tag];
    
    id compMenuItem;
    if ((flags & MPQFileDiabloCompressed)) {
        compressor = MPQPKWARECompression;
        compMenuItem = [[m_compressorMenu menu] itemWithTag:compressor];
        [m_compressorMenu selectItem:compMenuItem];
        [m_compressorMenu setEnabled:NO];
        [m_compressionLevelMenu selectItem:nil];
        [m_compressionLevelMenu setEnabled:NO];
    } else {
        [m_compressorMenu setEnabled:YES];
        if (compressor != 0)
			flags |= MPQFileCompressed;
    }
    
    if (sender == m_compressorMenu) {
        if (compressor == MPQZLIBCompression) {
            [m_compressionLevelMenu setMenu:m_zlibQualityMenu];
            [m_compressionLevelMenu selectItemAtIndex:0];
            [m_compressionLevelMenu setEnabled:YES];
        } else if (compressor == MPQBZIP2Compression) {
            [m_compressionLevelMenu setMenu:m_bzip2QualityMenu];
            [m_compressionLevelMenu selectItemAtIndex:0];
            [m_compressionLevelMenu setEnabled:YES];
        } else {
            [m_compressionLevelMenu selectItem:nil];
            [m_compressionLevelMenu setEnabled:NO];
        }
    }
    
    int quality = 0;
    compMenuItem = [m_compressionLevelMenu selectedItem];
    if (compMenuItem)
		quality = [compMenuItem tag];
    
    NSDictionary *importDict = [NSDictionary dictionaryWithObjectsAndKeys:
        NSInt(flags), MPQFileFlags,
        NSInt(compressor), MPQCompressor,
        NSInt(quality), MPQCompressionQuality,
        NSInt(MPQNeutral), MPQFileLocale,
        [NSNumber numberWithBool:[m_replaceCheckbox state]], MPQOverwrite,
        nil];
    
    [m_typeKeysArray addObject:PRESERVE_ARCHIVE_KEY];
    [m_typeKeysArray addObject:MAKE_IMP_KEY];
    [m_typeKeysArray addObject:DEFAULT_IMPORT_DICT_KEY];
    
    [m_typeValuesArray addObject:[[prefs objectForKey:DEFAULT_IMPORT_DICT_PREF] objectForKey:PRESERVE_ARCHIVE_KEY]];
    [m_typeValuesArray addObject:[[prefs objectForKey:DEFAULT_IMPORT_DICT_PREF] objectForKey:MAKE_IMP_KEY]];
    [m_typeValuesArray addObject:importDict];
    
    NSDictionary *defaultImportDict = [NSDictionary dictionaryWithObjects:m_typeValuesArray forKeys:m_typeKeysArray];
    
    [m_typeKeysArray removeObjectsInRange:NSMakeRange([m_typeKeysArray count] - 3, 3)];
    [m_typeValuesArray removeObjectsInRange:NSMakeRange([m_typeValuesArray count] - 3, 3)];
        
    [prefs setObject:defaultImportDict forKey:DEFAULT_IMPORT_DICT_PREF];
}

/* NSTableView data source delegate methods */

- (int)numberOfRowsInTableView:(NSTableView *)aTableView {
    [self updateExceptionSettings:self];
    return [m_typeKeysArray count];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex {
    return [m_typeKeysArray objectAtIndex:rowIndex];
}

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex {
    NSImage *typeIcon = [[NSWorkspace sharedWorkspace] iconForFileType:[m_typeKeysArray objectAtIndex:rowIndex]];
    if (!typeIcon)
		NSLog(@"Could not get the icon for %@",[m_typeKeysArray objectAtIndex:rowIndex]);
    [typeIcon setScalesWhenResized:YES];
    [typeIcon setSize:NSMakeSize(32,32)];
    
    [aCell setImage:typeIcon];
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex {
    [m_typeKeysArray replaceObjectAtIndex:rowIndex withObject:anObject];
    return;
}

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)aTableView {
    return !m_isEditing;
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
    int selection = [m_typeTable selectedRow];
    if (selection == -1)
		return;
    
    if (m_madeNewEntry && selection == m_editedCell) {
        m_madeNewEntry = NO;
        [m_typeTable editColumn:0 row:selection withEvent:nil select:YES];
    }
    
    [self updateExceptionSettings:self];
}

- (BOOL)control:(NSControl *)control textShouldEndEditing:(NSText *)fieldEditor {
    NSString *ext = [fieldEditor string];
    
    if ([ext length] == 0) {
        if (![m_typeKeysArray objectAtIndex:m_editedCell] || [[m_typeKeysArray objectAtIndex:m_editedCell] isEqualToString:@""])
			return NO;
        else
			[fieldEditor setString:[m_typeKeysArray objectAtIndex:m_editedCell]];
    } else if ([m_typeKeysArray containsObject:ext])
        return NO;
        
    return YES;
}

- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex {
    m_isEditing = YES;
    m_editedCell = rowIndex;
    return YES;
}

- (void)controlTextDidBeginEditing:(NSNotification *)aNotification {
    m_isEditing = YES;
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification {
    if ([m_typeKeysArray count] > 0) {
        NSTableColumn *tableColumn = [m_typeTable tableColumnWithIdentifier:@"filetype"];
        [self tableView:m_typeTable willDisplayCell:[tableColumn dataCell] forTableColumn:tableColumn row:m_editedCell];
    }
    
    m_isEditing = NO;
}

- (IBAction)updateExceptionSettings:(id)sender {
    int selection = [m_typeTable selectedRow];
    if (selection == -1 || [m_typeValuesArray count] <= selection)
		return;
    NSDictionary *importDict = [m_typeValuesArray objectAtIndex:selection];
    
    int flags = [[importDict objectForKey:MPQFileFlags] intValue];
    int compressor = [[importDict objectForKey:MPQCompressor] intValue];
    
    if ((flags & MPQFileDiabloCompressed)) {
        compressor = MPQPKWARECompression;
        [m_compressorCustomMenu setEnabled:NO];
    } else
		[m_compressorCustomMenu setEnabled:YES];
    
    id compMenuItem = [[m_compressorCustomMenu menu] itemWithTag:compressor];
    if (compMenuItem)
		[m_compressorCustomMenu selectItem:compMenuItem];
    else {
        compressor = MPQZLIBCompression;
        flags &= ~MPQFileDiabloCompressed;
        
        compMenuItem = [[m_compressorCustomMenu menu] itemWithTag:compressor];
        NSAssert(compMenuItem != nil, @"compMenuItem was nil for MPQZLIBCompression");
        [m_compressorCustomMenu selectItem:compMenuItem];
    }

    [m_encryptFileCustomCheckbox setState:(flags & MPQFileEncrypted) ? YES : NO];
    [m_replaceCustomCheckbox setState:[[importDict objectForKey:MPQOverwrite] boolValue]];
    [m_offsetKeyCustomCheckbox setState:(flags & MPQFileOffsetAdjustedKey) ? YES : NO];
    [m_diabloCompCustomCheckbox setState:(flags & MPQFileDiabloCompressed) ? YES : NO];
    
    if (compressor == MPQZLIBCompression) {
        [m_compressionLevelCustomMenu setMenu:m_zlibQualityCustomMenu];
        [m_compressionLevelCustomMenu setEnabled:YES];
    } else if (compressor == MPQBZIP2Compression) {
        [m_compressionLevelCustomMenu setMenu:m_bzip2QualityCustomMenu];
        [m_compressionLevelCustomMenu setEnabled:YES];
    } else if (compressor == (MPQStereoADPCMCompression | MPQHuffmanTreeCompression)) {
        [m_compressionLevelCustomMenu setMenu:m_ADPCMQualityCustomMenu];
        [m_compressionLevelCustomMenu setEnabled:YES];
    } else {
        [m_compressionLevelCustomMenu selectItem:nil];
        [m_compressionLevelCustomMenu setEnabled:NO];
    }

    int quality = [[importDict objectForKey:MPQCompressionQuality] intValue];
    int defaultQuality;
    if (compressor == MPQZLIBCompression || compressor == MPQBZIP2Compression)
		defaultQuality = 9; // 9 = Z_BEST_COMPRESSION
    else if (compressor == (MPQStereoADPCMCompression | MPQHuffmanTreeCompression))
		defaultQuality = MPQADPCMQualityHigh;
    
    if ([m_compressionLevelCustomMenu isEnabled]) {
        NSMenuItem *compQualMenuItem = [[m_compressionLevelCustomMenu menu] itemWithTag:quality];
        if (compQualMenuItem)
			[m_compressionLevelCustomMenu selectItem:compQualMenuItem];
        else {
            quality = defaultQuality;
            compQualMenuItem = [[m_compressionLevelCustomMenu menu] itemWithTag:quality];
            NSAssert(compMenuItem != nil, @"compQualMenuItem was nil for the default compression quality of the selected compressor");
            [m_compressionLevelCustomMenu selectItem:compQualMenuItem];
        }
    }
}

- (IBAction)saveExceptionSettings:(id)sender {
    int selection = [m_typeTable selectedRow];
    if (selection == -1)
		return;
    
    int flags = 0;
    if ([m_encryptFileCustomCheckbox state])
		flags |= MPQFileEncrypted;
    if ([m_offsetKeyCustomCheckbox state])
		flags |= MPQFileOffsetAdjustedKey;
    if ([m_diabloCompCustomCheckbox state])
		flags |= MPQFileDiabloCompressed;
    
    int compressor = [[m_compressorCustomMenu selectedItem] tag];
    
    id compMenuItem;
    if ((flags & MPQFileDiabloCompressed)) {
        compressor = MPQPKWARECompression;
        compMenuItem = [[m_compressorCustomMenu menu] itemWithTag:compressor];
        [m_compressorCustomMenu selectItem:compMenuItem];
        [m_compressorCustomMenu setEnabled:NO];
        [m_compressionLevelCustomMenu selectItem:nil];
        [m_compressionLevelCustomMenu setEnabled:NO];
    } else {
        [m_compressorCustomMenu setEnabled:YES];
        if (compressor != 0)
			flags |= MPQFileCompressed;
    }
    
    if (sender == m_compressorCustomMenu) {
        if (compressor == MPQZLIBCompression) {
            [m_compressionLevelCustomMenu setMenu:m_zlibQualityCustomMenu];
            [m_compressionLevelCustomMenu selectItemAtIndex:0];
            [m_compressionLevelCustomMenu setEnabled:YES];
        } else if (compressor == MPQBZIP2Compression) {
            [m_compressionLevelCustomMenu setMenu:m_bzip2QualityCustomMenu];
            [m_compressionLevelCustomMenu selectItemAtIndex:0];
            [m_compressionLevelCustomMenu setEnabled:YES];
        } else if (compressor == (MPQStereoADPCMCompression | MPQHuffmanTreeCompression)) {
            [m_compressionLevelCustomMenu setMenu:m_ADPCMQualityCustomMenu];
            [m_compressionLevelCustomMenu selectItemAtIndex:0];
            [m_compressionLevelCustomMenu setEnabled:YES];
        } else {
            [m_compressionLevelCustomMenu selectItem:nil];
            [m_compressionLevelCustomMenu setEnabled:NO];
        }
    }
    
    int quality = 0;
    compMenuItem = [m_compressionLevelCustomMenu selectedItem];
    if (compMenuItem)
		quality = [compMenuItem tag];
    
    NSDictionary *importDict = [NSDictionary dictionaryWithObjectsAndKeys:
        NSInt(flags), MPQFileFlags,
        NSInt(compressor), MPQCompressor,
        NSInt(quality), MPQCompressionQuality,
        NSInt(MPQNeutral), MPQFileLocale,
        [NSNumber numberWithBool:[m_replaceCustomCheckbox state]], MPQOverwrite,
        nil];
    
    [m_typeValuesArray replaceObjectAtIndex:selection withObject:importDict];
    [self savePreferencesAction:sender];
}

- (IBAction)writeOutDict:(id)sender {
    NSOpenPanel *chooseDirPanel = [NSOpenPanel openPanel];
    [chooseDirPanel setCanChooseFiles:NO];
    [chooseDirPanel setCanChooseDirectories:YES];
    [chooseDirPanel setAllowsMultipleSelection:NO];
    [chooseDirPanel setTitle:@"Select Destination"];
    [chooseDirPanel setPrompt:@"Select"];

    int returnCode = [chooseDirPanel runModalForTypes:nil];
    if (returnCode == NSOKButton) {
        [self saveExceptionSettings:self];
        [self savePreferencesAction:self];
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        NSDictionary *defaultImportDict = [prefs objectForKey:DEFAULT_IMPORT_DICT_PREF];
        [defaultImportDict writeToFile:[[[chooseDirPanel filenames] objectAtIndex:0] stringByAppendingPathComponent:@"mpq.plist"] atomically:YES];
    }
}

@end
