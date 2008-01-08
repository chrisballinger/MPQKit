//
//  MPQFilePrivate.h
//  MPQKit
//
//  Created by Jean-Francois Roy on Mon Jun 07 2007.
//  Copyright (c) 2002-2007 MacStorm. All rights reserved.
//

#import <MPQKit/MPQFile.h>

@interface MPQFile (MPQFilePrivate)
- (NSData *)_copyRawSector:(uint32_t)index error:(NSError **)error;
@end

