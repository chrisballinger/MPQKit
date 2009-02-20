#import <PreferencePanes/PreferencePanes.h>

#import "MVPreferencesController.h"
#import "MVPreferencesMultipleIconView.h"
#import "MVPreferencesGroupedIconView.h"

static MVPreferencesController *sharedInstance = nil;

static NSString *MVToolbarShowAllItemIdentifier = @"MVToolbarShowAllItem";
NSString *MVPreferencesWindowNotification = @"MVPreferencesWindowNotification";

@interface NSToolbar (NSToolbarPrivate)
- (NSView *) _toolbarView;
@end

@interface MVPreferencesController (MVPreferencesControllerPrivate)
- (void) _doUnselect:(NSNotification *) notification;
- (IBAction) _selectPreferencePane:(id) sender;
- (void) _resizeWindowForContentView:(NSView *) view;
- (NSImage *) _imageForPaneBundle:(NSBundle *) bundle;
- (NSString *) _paletteLabelForPaneBundle:(NSBundle *) bundle;
- (NSString *) _labelForPaneBundle:(NSBundle *) bundle;
@end

@implementation MVPreferencesController

+ (MVPreferencesController *) sharedInstance {
    return ( sharedInstance ? sharedInstance : [[[self alloc] init] autorelease] );
}

- (id) init {
    if( ( self = [super init] ) ) {
		unsigned i = 0;
		
		panes = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"PreferencePanes"] mutableCopy];
		
		loadedPanes = [[NSMutableDictionary dictionary] retain];
		paneInfo = [[NSMutableDictionary dictionary] retain];
		
		[NSBundle loadNibNamed:@"MVPreferences" owner:self];
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector( _doUnselect: ) name:@"MVPreferencesDoUnselectNotification" object:nil];
    }
    
	return self;
}

- (void) dealloc {
    [loadedPanes release];
    [panes release];
    [paneInfo release];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
    
	loadedPanes = nil;
    panes = nil;
    paneInfo = nil;
    
	[super dealloc];
}

- (void) awakeFromNib {
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"Main Preference Toolbar"];
    NSArray *groups = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"MVPreferencePaneGroups" ofType:@"plist"]];
	NSMutableDictionary *toolbarItems;
	
	if( groups ) {
	    [groupView setPreferencePanes:panes];
	    [groupView setPreferencePaneGroups:groups];
	    mainView = groupView;
	} else {
	    [multiView setPreferencePanes:panes];
	    mainView = multiView;
	}
	
	[self showAll:nil];
	
	[window setDelegate:self];
	
	[toolbar setAutosavesConfiguration:YES];
	[toolbar setAllowsUserCustomization:NO];
	[toolbar setDelegate:self];
	
	//	[toolbar setShowsContextMenu:NO];
	[window setToolbar:toolbar];
	
	toolbarItems = [[toolbar configurationDictionary] mutableCopy];
	[toolbarItems setObject:[self toolbarDefaultItemIdentifiers:toolbar] forKey:@"TB Item Identifiers"];
	[toolbar setConfigurationFromDictionary:toolbarItems];
	[toolbarItems release];
	
	//	[toolbar setIndexOfFirstMovableItem:4];
	[toolbar release];
}

- (NSWindow *) window {
    return [[window retain] autorelease];
}

- (IBAction) showPreferences:(id) sender {
    [self showAll:nil];
	[window center];
    [window makeKeyAndOrderFront:nil];
}

- (IBAction)nextButton:(id)sender
{
    NSMutableArray *identifiers = [[NSMutableArray alloc] initWithArray: [self toolbarAllowedItemIdentifiers: nil]];
    
    if ( [identifiers count] )
		[identifiers removeObjectAtIndex: [identifiers count] - 1];
    
	int currentIndex = -1;
    int indexToLoad = 0;
    
	if ( currentPaneIdentifier )
		currentIndex = [identifiers indexOfObject: currentPaneIdentifier];
    
    if ( currentIndex >= 0 )
		indexToLoad = currentIndex + 1;
    
    if ( indexToLoad >= [identifiers count] )
		indexToLoad = 0;
    
    [self selectPreferencePaneByIdentifier: [identifiers objectAtIndex: indexToLoad]];
    [identifiers release];
}

- (IBAction)previousButton:(id)sender
{
    NSMutableArray *identifiers = [[NSMutableArray alloc] initWithArray: [self toolbarAllowedItemIdentifiers: nil]];
    
    if ( [identifiers count] )
		[identifiers removeObjectAtIndex: [identifiers count] - 1];
    int currentIndex = -1;
    int indexToLoad = [identifiers count] - 1;
    
    if ( currentPaneIdentifier )
		currentIndex = [identifiers indexOfObject: currentPaneIdentifier];
    
    if ( currentIndex >= 0 )
		indexToLoad = currentIndex - 1;
    
    if ( indexToLoad < 0 )
		indexToLoad = [identifiers count] - 1;
    
    [self selectPreferencePaneByIdentifier: [identifiers objectAtIndex: indexToLoad]];
    [identifiers release];
}

- (IBAction) showAll:(id) sender {
    if( [[window contentView] isEqual:mainView] ) return;
    
	if( currentPaneIdentifier && [[loadedPanes objectForKey:currentPaneIdentifier] shouldUnselect] != NSUnselectNow ) {
		/* more to handle later */
		NSLog( @"can't unselect current" );
		return;
    }
    
    NSMutableArray *identifiers = [[NSMutableArray alloc] initWithArray: [self toolbarAllowedItemIdentifiers: nil]];
	
	if ( [panes count] )
    {
		if ( !currentPaneIdentifier ) {
			[self selectPreferencePaneByIdentifier:[identifiers objectAtIndex: 0]];
		} else if ( [[window toolbar] respondsToSelector: @selector(setSelectedItemIdentifier:)] ) {
			[[window toolbar] setSelectedItemIdentifier: currentPaneIdentifier];
		}
		
    }
    else if ( !currentPaneIdentifier )
    {
		[window setContentView:[[[NSView alloc] initWithFrame:[mainView frame]] autorelease]];
		
		[window setTitle:[NSString stringWithFormat:NSLocalizedString( @"%@ Preferences", nil ), [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleName"]]];
		[self _resizeWindowForContentView:mainView];
		
		[[loadedPanes objectForKey:currentPaneIdentifier] willUnselect];
		[window setContentView:mainView];
		[[loadedPanes objectForKey:currentPaneIdentifier] didUnselect];
		
		[currentPaneIdentifier release];
		currentPaneIdentifier = nil;
		
		[window setInitialFirstResponder:mainView];
		[window makeFirstResponder:mainView];
    }
	
	[identifiers release];
}

- (void) selectPreferencePaneByIdentifier:(NSString *) identifier {
    NSBundle *bundle = [NSBundle bundleWithIdentifier:identifier];
    if( bundle && ! [currentPaneIdentifier isEqualToString:identifier] ) {
		NSPreferencePane *pane = nil;
		NSView *prefView = nil;
		if( currentPaneIdentifier && [[loadedPanes objectForKey:currentPaneIdentifier] shouldUnselect] != NSUnselectNow ) {
			/* more to handle later */
			NSLog( @"can't unselect current" );
			closeWhenPaneIsReady = NO;
			
			[pendingPane release];
			pendingPane = [identifier retain];
			
			return;
		}
		
		[pendingPane release];
		pendingPane = nil;
		
		[loadingImageView setImage:[self _imageForPaneBundle:bundle]];
		[loadingTextFeld setStringValue:[NSString stringWithFormat:NSLocalizedString( @"Loading %@...", nil ), [self _labelForPaneBundle:bundle]]];
		
		[window setTitle:[self _labelForPaneBundle:bundle]];
		[window setContentView:loadingView];
		[window display];
		
		if( ! ( pane = [loadedPanes objectForKey:identifier] ) ) {
			pane = [[[[bundle principalClass] alloc] initWithBundle:bundle] autorelease];
			if( pane ) [loadedPanes setObject:pane forKey:identifier];
		}
		
		if( [pane loadMainView] ) {
			[pane willSelect];
			prefView = [pane mainView];
			
			[self _resizeWindowForContentView:prefView];
			
			[[loadedPanes objectForKey:currentPaneIdentifier] willUnselect];
			
			[window setContentView:prefView];
			[[loadedPanes objectForKey:currentPaneIdentifier] didUnselect];
			
			[pane didSelect];
			
			[[NSNotificationCenter defaultCenter] postNotificationName:MVPreferencesWindowNotification object:self userInfo:[NSDictionary dictionaryWithObjectsAndKeys:window, @"window", nil]];
			
			[currentPaneIdentifier release];
			currentPaneIdentifier = [identifier copy];
			
			[window setInitialFirstResponder:[pane initialKeyView]];
			[window makeFirstResponder:[pane initialKeyView]];
		} else { 
			NSRunCriticalAlertPanel( NSLocalizedString( @"Preferences Error", nil ), 
									 [NSString stringWithFormat:NSLocalizedString( @"Could not load %@", nil ), 
										 [self _labelForPaneBundle:bundle]], 
									 nil, 
									 nil, 
									 nil );
		}
    }
    
	if ( [[window toolbar] respondsToSelector: @selector(setSelectedItemIdentifier:)] )
		[[window toolbar] setSelectedItemIdentifier: identifier];
}

- (BOOL) windowShouldClose:(id) sender {
    if( currentPaneIdentifier && [[loadedPanes objectForKey:currentPaneIdentifier] shouldUnselect] != NSUnselectNow ) {
		closeWhenPaneIsReady = YES;
		return NO;
    }
	
	return YES;
}

- (void) windowWillClose:(NSNotification *) notification {
    [[loadedPanes objectForKey:currentPaneIdentifier] willUnselect];
    [[loadedPanes objectForKey:currentPaneIdentifier] didUnselect];
    
	[currentPaneIdentifier release];
    currentPaneIdentifier = nil;
}

- (NSToolbarItem *) toolbar:(NSToolbar *) toolbar itemForItemIdentifier:(NSString *) itemIdentifier willBeInsertedIntoToolbar:(BOOL) flag {
    NSToolbarItem *toolbarItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];
    if( [itemIdentifier isEqualToString:MVToolbarShowAllItemIdentifier] ) {
		[toolbarItem setLabel:NSLocalizedString( @"Show All", nil )];
		[toolbarItem setImage:[NSImage imageNamed:@"AddContact"]];
		[toolbarItem setTarget:self];
		[toolbarItem setAction:@selector( showAll: )];
    } else if( [itemIdentifier isEqualToString:@"Previous Button"] ) {
		[toolbarItem setLabel:NSLocalizedString( @"Previous", nil )];
		[toolbarItem setImage:[NSImage imageNamed: @"PreferencesPreviousButton"]];
		[toolbarItem setTarget:self];
		[toolbarItem setAction:@selector( previousButton: )];
    } else if( [itemIdentifier isEqualToString:@"Next Button"] ) {
		[toolbarItem setLabel:NSLocalizedString( @"Next", nil )];
		[toolbarItem setImage:[NSImage imageNamed: @"PreferencesNextButton"]];
		[toolbarItem setTarget:self];
		[toolbarItem setAction:@selector( nextButton: )];
    } else {
		NSBundle *bundle = [NSBundle bundleWithIdentifier:itemIdentifier];
		if( bundle ) {
			[toolbarItem setLabel:[self _labelForPaneBundle:bundle]];
			[toolbarItem setPaletteLabel:[self _paletteLabelForPaneBundle:bundle]];
			[toolbarItem setImage:[self _imageForPaneBundle:bundle]];
			[toolbarItem setTarget:self];
			[toolbarItem setAction:@selector( _selectPreferencePane: )];
		} else toolbarItem = nil;
    }
    return toolbarItem;
}

- (NSArray *) toolbarSelectableItemIdentifiers:(NSToolbar *) toolbar {
    NSMutableArray *items = [NSMutableArray array];
    NSEnumerator *enumerator = [panes objectEnumerator];
    id item = nil;
    while( ( item = [enumerator nextObject] ) )
	[items addObject:[item bundleIdentifier]];
    return items;
}


- (NSArray *) toolbarDefaultItemIdentifiers:(NSToolbar *) toolbar {
    NSMutableArray * array = [[NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"MVPreferencePaneDefaults" ofType:@"plist"]] mutableCopy];
    int i;
    for ( i = 0 ; i < [array count] ; i++ )
    {
		if ( [[array objectAtIndex: i] isEqualToString: @"NSToolbarSpaceItemIdentifier"] )
			[array replaceObjectAtIndex: i withObject: NSToolbarSpaceItemIdentifier];
		if ( [[array objectAtIndex: i] isEqualToString: @"NSToolbarFlexibleSpaceItemIdentifier"] )
			[array replaceObjectAtIndex: i withObject: NSToolbarFlexibleSpaceItemIdentifier];
		if ( [[array objectAtIndex: i] isEqualToString: @"NSToolbarSeparatorItemIdentifier"] )
			[array replaceObjectAtIndex: i withObject: NSToolbarSeparatorItemIdentifier];
    }
    
	return [array autorelease];
}

- (NSArray *) toolbarAllowedItemIdentifiers:(NSToolbar *) toolbar {
    return [self toolbarDefaultItemIdentifiers: toolbar];
}

@end

@implementation MVPreferencesController (MVPreferencesControllerPrivate)
- (IBAction) _selectPreferencePane:(id) sender {
    [self selectPreferencePaneByIdentifier:[sender itemIdentifier]];
}

- (void) _doUnselect:(NSNotification *) notification {
    if( closeWhenPaneIsReady ) [window close];
    [self selectPreferencePaneByIdentifier:pendingPane];
}

- (void) _resizeWindowForContentView:(NSView *) view {
    NSRect windowFrame, newWindowFrame;
    unsigned int newWindowHeight;
    
    windowFrame = [NSWindow contentRectForFrameRect:[window frame] styleMask:[window styleMask]];
    newWindowHeight = NSHeight( [view frame] );
    if( [[window toolbar] isVisible] )
		newWindowHeight += NSHeight( [[[window toolbar] _toolbarView] frame] );
    
	newWindowFrame = [NSWindow frameRectForContentRect:NSMakeRect( NSMinX( windowFrame ), 
																   NSMaxY( windowFrame ) - newWindowHeight, 
																   NSWidth( windowFrame ), 
																   newWindowHeight ) 
											 styleMask:[window styleMask]];
    
    [window setFrame:newWindowFrame display:YES animate:[window isVisible]];
}

- (NSImage *) _imageForPaneBundle:(NSBundle *) bundle {
    NSImage *image = nil;
    NSMutableDictionary *cache = [paneInfo objectForKey:[bundle bundleIdentifier]];
    image = [[[cache objectForKey:@"MVPreferencePaneImage"] retain] autorelease];
    if( ! image ) {
		NSDictionary *info = [bundle infoDictionary];
		image = [[[NSImage alloc] initWithContentsOfFile:[bundle pathForImageResource:[info objectForKey:@"NSPrefPaneIconFile"]]] autorelease];
		if( ! image ) image = [[[NSImage alloc] initWithContentsOfFile:[bundle pathForImageResource:[info objectForKey:@"CFBundleIconFile"]]] autorelease];
		if( ! cache ) [paneInfo setObject:[NSMutableDictionary dictionary] forKey:[bundle bundleIdentifier]];
		cache = [paneInfo objectForKey:[bundle bundleIdentifier]];
		if( image ) [cache setObject:image forKey:@"MVPreferencePaneImage"];
    }
    
	return image;
}

- (NSString *) _paletteLabelForPaneBundle:(NSBundle *) bundle {
    NSString *label = nil;
    NSMutableDictionary *cache = [paneInfo objectForKey:[bundle bundleIdentifier]];
    label = [[[cache objectForKey:@"MVPreferencePanePaletteLabel"] retain] autorelease];
    if( ! label ) {
		NSDictionary *info = [bundle infoDictionary];
		label = NSLocalizedStringFromTableInBundle( @"NSPrefPaneIconLabel", @"InfoPlist", bundle, nil );
		if( [label isEqualToString:@"NSPrefPaneIconLabel"] ) label = [info objectForKey:@"NSPrefPaneIconLabel"];
		if( ! label ) label = NSLocalizedStringFromTableInBundle( @"CFBundleName", @"InfoPlist", bundle, nil );
		if( [label isEqualToString:@"CFBundleName"] ) label = [info objectForKey:@"CFBundleName"];
		if( ! label ) label = [bundle bundleIdentifier];
		if( ! cache ) [paneInfo setObject:[NSMutableDictionary dictionary] forKey:[bundle bundleIdentifier]];
		cache = [paneInfo objectForKey:[bundle bundleIdentifier]];
		if( label ) [cache setObject:label forKey:@"MVPreferencePanePaletteLabel"];
    }
    
	return label;
}

- (NSString *) _labelForPaneBundle:(NSBundle *) bundle {
    NSString *label = nil;
    NSMutableDictionary *cache = [paneInfo objectForKey:[bundle bundleIdentifier]];
    label = [[[cache objectForKey:@"MVPreferencePaneLabel"] retain] autorelease];
    if( ! label ) {
		NSDictionary *info = [bundle infoDictionary];
		label = NSLocalizedStringFromTableInBundle( @"CFBundleName", @"InfoPlist", bundle, nil );
		if( [label isEqualToString:@"CFBundleName"] ) label = [info objectForKey:@"CFBundleName"];
		if( ! label ) label = [bundle bundleIdentifier];
		if( ! cache ) [paneInfo setObject:[NSMutableDictionary dictionary] forKey:[bundle bundleIdentifier]];
		cache = [paneInfo objectForKey:[bundle bundleIdentifier]];
		if( label ) [cache setObject:label forKey:@"MVPreferencePaneLabel"];
    }
    return label;
}

@end
