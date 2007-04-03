#import <Foundation/Foundation.h>
#import <MPQKit/MPQKit.h>

CFStringEncoding CFStringFileSystemEncoding(void);

int main(int argc, char *argv[]) {
    NSAutoreleasePool *p = [NSAutoreleasePool new];
    int i = 1;
    for (; i < argc; i++) {
        if (i > 1) printf("\n");
        
        NSString *archivePath = [NSString stringWithCString:argv[i] encoding:CFStringConvertEncodingToNSStringEncoding(CFStringFileSystemEncoding())];
        MPQArchive *archive = [[MPQArchive alloc] initWithPath:archivePath];
        if (!archive) {
            printf("%s: INVALID ARCHIVE\n", [archivePath UTF8String]);
            continue;
        } else {
            printf("Checking %s...\n", [archivePath UTF8String]);
        }
        
        BOOL isSigned;
        NSError *error = nil;
        BOOL valid = [archive verifyBlizzardWeakSignature:&isSigned error:&error];
        if (valid) printf("Blizzard weak signature: VALID\n");
        else if (isSigned && !error) printf("Blizzard weak signature: INVALID\n");
        else if (isSigned) printf("Blizzard weak signature: ERROR: %s\n", [[error description] UTF8String]);
        else printf("No weak signature\n");
        
        isSigned = [archive hasStrongSignature];
        if (isSigned) {
            valid = [archive verifyBlizzardStrongSignature:&error];
            if (valid) printf("Blizzard strong signature: VALID\n");
            else if (!error) printf("Blizzard strong signature: INVALID\n");
            else printf("Blizzard strong signature: ERROR: %s\n", [[error description] UTF8String]);
            
            valid = [archive verifyWoWSurveySignature:&error];
            if (valid) printf("WoW survey signature: VALID\n");
            else if (!error) printf("WoW survey signature: INVALID\n");
            else printf("Blizzard strong signature: ERROR: %s\n", [[error description] UTF8String]);
            
            valid = [archive verifyWoWMacPatchSignature:&error];
            if (valid) printf("WoW Macintosh patch signature: VALID\n");
            else if (!error) printf("WoW Macintosh patch signature: INVALID\n");
            else printf("Blizzard strong signature: ERROR: %s\n", [[error description] UTF8String]);
            
            valid = [archive verifyWarcraft3MapSignature:&error];
            if (valid) printf("Warcraft 3 map signature: VALID\n");
            else if (!error) printf("Warcraft 3 map signature: INVALID\n");
            else printf("Blizzard strong signature: ERROR: %s\n", [[error description] UTF8String]);
        } else {
            printf("No strong signature\n");
        }
    }
    
    [p release];
    return 0;
}
