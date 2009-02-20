//
//  miscPref.h
//  miscPref
//
//  Created by BahamutZERO on Fri Jul 18 2003.
//  Copyright (c) 2003 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <PreferencePanes/PreferencePanes.h>


@interface DQMiscellaneousPreferences : NSPreferencePane {
    IBOutlet NSButton* m_preserveArchiveButton;
    IBOutlet NSButton* m_makeImpButton;
}

- (IBAction)savePreferences:(id)sender;
- (void)mainViewDidLoad;

@end
