#import "FocusRingView.h"

@implementation FileDropView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self)
    {
        // Prepare drag and drop
        m_bFocusRing = FALSE;
        [self registerForDraggedTypes:[NSArray arrayWithObjects:NSFilenamesPboardType,nil]];
        
        m_multiFile = NO;
    }
    
    return self;
}

- (void)awakeFromNib
{
    if( ![delegate respondsToSelector:@selector(fileIsValidForDrop:)] || 
        ![delegate respondsToSelector:@selector(filesDropped:)] )
        delegate = nil;
}

- (void)dealloc
{
	[self unregisterDraggedTypes];
    [super dealloc];
}

- (id)delegate
{
    return delegate;
}

- (void)setDelegate:(id)anObject
{
    if( ![anObject respondsToSelector:@selector(fileIsValidForDrop:)] || 
        ![anObject respondsToSelector:@selector(filesDropped:)] )
        return;
    
    delegate = anObject;
}

- (BOOL)acceptMultipleFiles
{
    return m_multiFile;
}

- (void)setAcceptMultipleFiles:(BOOL)flag
{
    m_multiFile = flag;
}

- (void)drawRect:(NSRect)rect
{
	[super drawRect:rect];
    
    if(m_bFocusRing)
	{
		[[NSColor keyboardFocusIndicatorColor] set];
		[NSBezierPath setDefaultLineWidth:5];
        
        NSRect bounds = [self bounds];
        bounds.origin.x += 1.0;
        bounds.origin.y += 1.0;
        bounds.size.width -= 2.0;
        bounds.size.height -= 2.0;
        
		[NSBezierPath strokeRect:bounds];
	}
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    // Get the dragging-specific pasteboard from the sender
    NSPasteboard *paste = [sender draggingPasteboard];
    NSArray *fileArray = [paste propertyListForType:@"NSFilenamesPboardType"];
    [self setNeedsDisplay:YES];
    
    if((NSDragOperationGeneric & [sender draggingSourceOperationMask]) == NSDragOperationGeneric 
        && fileArray)
    {
        if(m_multiFile)
        {
            NSEnumerator *fileEnum = [fileArray objectEnumerator];
            NSString *aFile = nil;
            
            while ((aFile = [fileEnum nextObject]))
            {
                if(![delegate fileIsValidForDrop:aFile])
                {
                    m_bFocusRing = NO;
                    return NSDragOperationNone;
                }
            }
        }
        else
        {
            if(![delegate fileIsValidForDrop:[fileArray objectAtIndex:0]])
            {
                m_bFocusRing = NO;
                return NSDragOperationNone;
            }
        }
        
        m_bFocusRing = YES;
        return NSDragOperationGeneric;
    }
    
    m_bFocusRing = NO;
    return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
	m_bFocusRing = NO;
	[self setNeedsDisplay:YES];
	return;
}

- (void)draggingEnded:(id <NSDraggingInfo>)sender
{
	m_bFocusRing = NO;
	[self setNeedsDisplay:YES];
	return;
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
    return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
	// Get the dragging-specific pasteboard from the sender
	NSPasteboard *paste = [sender draggingPasteboard];
	
    // A list of types that we can accept
    NSArray *types = [NSArray arrayWithObjects:NSFilenamesPboardType, nil];
	
    NSString *desiredType = [paste availableTypeFromArray:types];
    NSData *carriedData = [paste dataForType:desiredType];

    if (carriedData == nil)
    {
        // The operation failed for some reason
        m_bFocusRing = NO;
		[self setNeedsDisplay:YES];
		return NO;
    }
    else
    {
        // The pasteboard was able to give us some meaningful data
        if ([desiredType isEqualToString:NSFilenamesPboardType])
        {
            // We have a list of file names in an NSData object
            NSArray *fileArray = [paste propertyListForType:@"NSFilenamesPboardType"];
            [delegate filesDropped:fileArray];
            
        }
        else
        {
            // This can't happen
            NSAssert(NO, @"This can't happen");
            m_bFocusRing = NO;
			[self setNeedsDisplay:YES];
			return NO;
        }
    }
    
	m_bFocusRing = NO;
    return YES;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
    [self setNeedsDisplay:YES];
	return;
}

@end
