/* DropMPQController */

#import <Cocoa/Cocoa.h>

#import "FocusRingView.h"
#import "RXVersionComparator.h"

enum { HAS_ITEM, NO_ITEM };

@interface DropMPQController : NSObject
{
    IBOutlet NSTextField *m_taskField;
    IBOutlet NSTextField *m_taskInfoField;
    IBOutlet NSProgressIndicator *m_progress;
	IBOutlet NSWindow *m_window;
	IBOutlet RXVersionComparator* comparator;
	
    NSMutableArray *m_foldersToProcess;
    
	BOOL m_isRunning;
    BOOL m_isProcessing;
	BOOL isAnimating;
	BOOL isIdle;
    
	NSConditionLock *m_dataLock;
	
	NSString *m_infoString;
    unsigned int m_fTotal;
    double m_fLeft;
	int m_displayMode;
	
	NSTimer *ui_tick;
    
	BOOL _blewPrefsAway;
}

- (IBAction)openDocument:(id)sender;
- (IBAction)displayPreferences:(id)sender;

- (void)filesDropped:(NSArray *)items;

- (void)processFolderThread:(id)object;
- (void)updateUI:(id)anObject;

@end
