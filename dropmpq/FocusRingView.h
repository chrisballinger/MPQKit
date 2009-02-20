#import <Cocoa/Cocoa.h>

@interface FileDropView : NSView
{
    IBOutlet id delegate;
    
    BOOL m_bFocusRing;
    BOOL m_multiFile;
}

- (id)delegate;
- (void)setDelegate:(id)anObject;

- (BOOL)acceptMultipleFiles;
- (void)setAcceptMultipleFiles:(BOOL)flag;

@end

@interface NSObject (FileDropViewDelegate)

- (BOOL)fileIsValidForDrop:(NSString *)path;
- (void)filesDropped:(NSArray *)paths;

@end
