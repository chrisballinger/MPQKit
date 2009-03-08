//
//  DQPreferenceWindowController.h
//  MPQKit
//
//  Created by Jean-Francois Roy on 08/03/2009.
//  Copyright 2009 MacStorm. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "DQPreferenceController.h"


@interface DQPreferenceWindowController : NSWindowController {
	IBOutlet DQPreferenceController* importPreferenceController;
	IBOutlet DQPreferenceController* miscPreferenceController;
}

@end
