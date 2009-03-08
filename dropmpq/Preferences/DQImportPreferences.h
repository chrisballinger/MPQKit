//
//  importPref.h
//  importPref
//
//  Created by BahamutZERO on Sat May 17 2003.
//  Copyright (c) 2003 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "DQPreferenceController.h"

@interface DQImportPreferences : DQPreferenceController {
    IBOutlet NSTabView *m_tabView;
    
    IBOutlet NSPopUpButton *m_compressionLevelMenu;
    IBOutlet NSPopUpButton *m_compressorMenu;
    IBOutlet NSMenu *m_zlibQualityMenu;
    IBOutlet NSMenu *m_bzip2QualityMenu;
    
    IBOutlet NSButton *m_diabloCompCheckbox;
    IBOutlet NSButton *m_encryptFileCheckbox;
    IBOutlet NSButton *m_offsetKeyCheckbox;
    IBOutlet NSButton *m_replaceCheckbox;
    
    IBOutlet NSPopUpButton *m_compressorCustomMenu;
    IBOutlet NSPopUpButton *m_compressionLevelCustomMenu;
    IBOutlet NSMenu *m_zlibQualityCustomMenu;
    IBOutlet NSMenu *m_bzip2QualityCustomMenu;
    IBOutlet NSMenu *m_ADPCMQualityCustomMenu;
    
    IBOutlet NSTableView *m_typeTable;
    
    IBOutlet NSButton *m_diabloCompCustomCheckbox;
    IBOutlet NSButton *m_encryptFileCustomCheckbox;
    IBOutlet NSButton *m_offsetKeyCustomCheckbox;
    IBOutlet NSButton *m_replaceCustomCheckbox;
    
    NSMutableArray *m_typeKeysArray;
    NSMutableArray *m_typeValuesArray;
    BOOL m_isEditing;
    int m_editedCell;
    BOOL m_madeNewEntry;
    int m_newCount;
}

- (IBAction)savePreferencesAction:(id)sender;
- (IBAction)updateExceptionSettings:(id)sender;
- (IBAction)saveExceptionSettings:(id)sender;
- (IBAction)writeOutDict:(id)sender;

- (void)mainViewDidLoad;

@end
