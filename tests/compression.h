//
//  compression.h
//  MPQKit
//
//  Created by Jean-François Roy on 02/06/2007.
//  Copyright 2007 MacStorm. All rights reserved.
//

#import <SenTestingKit/SenTestingKit.h>


@interface compression : SenTestCase {
@public
    void *random_buffer;
    void *compression_buffer;
    void *decompression_buffer;
}

@end
