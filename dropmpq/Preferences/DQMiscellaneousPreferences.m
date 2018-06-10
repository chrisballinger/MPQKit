//
//  miscPref.m
//  miscPref
//
//  Created by BahamutZERO on Fri Jul 18 2003.
//  Copyright (c) 2003 MacStorm. All rights reserved.
//

#import "DQMiscellaneousPreferences.h"
#import "PreferenceKeys.h"

#define NSPrefLocalizedString(key, comment) \
	    [[self bundle] localizedStringForKey:(key) value:@"" table:nil]
        
#define NSInt(a) ([NSNumber numberWithInt:a])

@implementation DQMiscellaneousPreferences

- (void)mainViewDidLoad {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSDictionary *defaultImportDict = [prefs objectForKey:DEFAULT_IMPORT_DICT_PREF];
    
    [m_preserveArchiveButton setState:[[defaultImportDict objectForKey:PRESERVE_ARCHIVE_KEY] intValue]];
    [m_makeImpButton setState:[[defaultImportDict objectForKey:MAKE_IMP_KEY] intValue]];
}

- (IBAction)savePreferences:(id)sender {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *defaultImportDict = [[prefs objectForKey:DEFAULT_IMPORT_DICT_PREF] mutableCopy];
    
    [defaultImportDict setObject:NSInt([m_preserveArchiveButton state]) forKey:PRESERVE_ARCHIVE_KEY];
    [defaultImportDict setObject:NSInt([m_makeImpButton state]) forKey:MAKE_IMP_KEY];
    
    [prefs setObject:defaultImportDict forKey:DEFAULT_IMPORT_DICT_PREF];
}

@end
