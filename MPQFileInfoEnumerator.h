//
//  _MPQFileInfoEnumerator.h
//  MPQKit
//
//  Created by Anarchie on Fri Oct 18 2002.
//  Contrinuted by Jean-Francois Roy
//  Copyright (c) 2002-2007 David Vierra. All rights reserved.
//

#import <Foundation/NSEnumerator.h>

@class MPQArchive;

@interface _MPQFileInfoEnumerator : NSEnumerator {
    MPQArchive *_archive;
    uint32_t _position;
}

+ (id)enumeratorWithArchive:(MPQArchive*)archive;
- (id)initWithArchive:(MPQArchive*)archive;

@end
