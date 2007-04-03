//
//  MPQFile.h
//  MPQKit
//
//  Created by Jean-Francois Roy on Mon Sep 30 2002.
//  Copyright (c) 2002 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MPQKit/MPQSharedConstants.h>

/*!
  @header MPQFile.h
  This header is automatically included by MPQKit.h and provides the definition of MPQFile.
*/

@class MPQArchive;

/*!
    @class MPQFile
    @abstract MPQFile is the root class of a class cluster responsible for reading MPQ files. 
        It can be used for simple one-time extraction or for data streaming.
    @discussion MPQFile is both designed and fast enough to be used for file streaming. Indeed, 
        MPQFile objects maintain an internal file pointer, much like NSFileHandle objects. 
        Whenever you read some data from an MPQFile object, the file pointer is increased by the 
        number of bytes read. As such, you may simply repeatedly call the readDataOfLength: 
        method to stream a file. MPQFile offer other facilities, such as seeking and file 
        information.
        
        You should not create MPQFile objects on your own, since MPQFile is the root class of a class cluster.
        Rather, use MPQArchive's openFile methods to get an MPQFile object for a given MPQ file.
*/
@interface MPQFile : NSObject {
    NSString *filename;
    MPQArchive *parent;
    uint32_t file_pointer;
    
    uint32_t hash_position;
    mpq_hash_table_entry_t hash_entry;
    mpq_block_table_entry_t block_entry;
}

/*! 
    @method name
    @abstract Returns the file's MPQ path.
    @discussion Note that the path separator is \.
    @result An NSString containing the file's path.
*/
- (NSString *)name;

/*! 
    @method length
    @abstract Returns the file's uncompressed length.
    @discussion If you are going to use atomical writing, you'll need twice that amount of 
        space on the target disk to extract the file.
    @result The file's uncompressed length as an integer.
*/
- (uint32_t)length;

/*! 
    @method fileInfo
    @abstract Returns the information dictionary for the file.
    @discussion For details on the keys that will be in the information dictionary, 
        see the documentation for fileInfoForPosition: in MPQArchive.
    @result An NSDictionary object containing the file's information. nil on failure.
*/
- (NSDictionary *)fileInfo;
- (NSDictionary *)fileInfo:(NSError **)error;

/*! 
    @method seekToFileOffset:
    @abstract Seeks to the specified file offset.
    @discussion Note that this method simply calls seekToFileOffset:withMode: with the MPQFileBegin mode.
    @param offset The number of bytes to move from the beginning of the file as an unsigned integer.
    @result The new file position, or -1 on error.
    
*/
- (uint32_t)seekToFileOffset:(uint32_t)offset;
- (uint32_t)seekToFileOffset:(uint32_t)offset error:(NSError **)error;

/*! 
    @method seekToFileOffset:mode:
    @abstract Seeks the number of specified bytes from the specified starting point.
    @discussion The valid displacement modes are: 
    
        * MPQFileStart: Seeking is done with respect to the beginning of the file 
        and toward the end of file. In effect, this makes nDistanceToMove an absolute 
        file offset to seek to.
        
        * MPQFileCurrent: Seeking is done with respect to the current file pointer 
        and toward the end of file. If nDistanceToMove will move the file pointer 
        beyond the end of file, the file pointer is moved to the end of file.
        
        * MPQFileEnd: Seeking is done with respect to the end of file and toward 
        the beginning of the file. If nDistanceToMove will move the file pointer 
        to a negative position, the file pointer is moved to the beginning of the 
        file.
    @param offset The number of bytes to move from the beginning of the file as an unsigned integer.
    @param mode The displacement method. Must be a valid MPQFileDisplacementMode constant. 
        Will affect the interpretation of distanceToMove.
    @result The new file position, or -1 on error.
*/
- (uint32_t)seekToFileOffset:(uint32_t)offset mode:(MPQFileDisplacementMode)mode;
- (uint32_t)seekToFileOffset:(uint32_t)offset mode:(MPQFileDisplacementMode)mode error:(NSError **)error;

/*! 
    @method offsetInFile
    @abstract Returns position of the file pointer with respect to the beginning of the file.
    @discussion This should always return 0 for newly created MPQFile instances.
    @result The position of the file pointer as an integer.
*/
- (uint32_t)offsetInFile;

/*! 
    @method eof
    @abstract Returns the end of file state of the file.
    @discussion Returns YES when bytes were read up to or past the end of file, or when the file 
        cursor is moved past the last byte.
    @result YES if the file pointer is at the end of file, NO otherwise.
*/
- (BOOL)eof;

/*! 
    @method copyDataOfLength:
    @abstract Reads the specified number of bytes in the file starting at 
        the position of the file pointer and returns an NSData container.
    @discussion IMPORTANT: The size of the returned data may actually be smaller than the number of 
        requested bytes, if the number of requested bytes would cause the file pointer 
        to go beyond the end of file.
        
        The file pointer is incremented by the number of bytes returned.
        
        Note that the returned NSData object is not autoreleased and so its ownership is transferred
        to the caller. Because the NSData object is not autoreleased, this method will offer much 
        better performances in tight loops due to the large overhead of the autorelease mechanism.
    @param length The number of bytes to read.
    @result An NSData object containing the requested bytes (or less). nil on failure.
*/
- (NSData *)copyDataOfLength:(uint32_t)length;
- (NSData *)copyDataOfLength:(uint32_t)length error:(NSError **)error;

/*! 
    @method copyDataToEndOfFile
    @abstract Reads the file starting at the position of the file pointer down to
        the end of file.
    @discussion IMPORTANT: The size of the returned data may actually be smaller than the number of 
        requested bytes, if the number of requested bytes would cause the file pointer 
        to go beyond the end of file.
        
        The file pointer is incremented by the number of bytes returned.
        
        Note that this method simply calls the copyDataOfLength: method with the number 
        of bytes to read set to whatever value will move the file pointer to the end of file.
        
        Note that the returned NSData object is not autoreleased and so its ownership is transferred
        to the caller. Because the NSData object is not autoreleased, this method will offer much 
        better performances in tight loops due to the large overhead of the autorelease mechanism.
    @result An NSData object containing the bytes from the old file pointer down to the
        end of file. nil on failure.
*/
- (NSData *)copyDataToEndOfFile;
- (NSData *)copyDataToEndOfFile:(NSError **)error;

/*! 
    @method getDataOfLength:
    @abstract Reads the specified number of bytes in the file starting at 
        the position of the file pointer and returns an autoreleased NSData container.
    @discussion IMPORTANT: The size of the returned data may actually be smaller than the number of 
        requested bytes, if the number of requested bytes would cause the file pointer 
        to go beyond the end of file.
        
        The file pointer is incremented by the number of bytes returned.
    @param length The number of bytes to read.
    @result An autoreleased NSData object containing the requested bytes (or less). nil on failure.
*/
- (NSData *)getDataOfLength:(uint32_t)length;
- (NSData *)getDataOfLength:(uint32_t)length error:(NSError **)error;

/*! 
    @method getDataToEndOfFile
    @abstract Reads the file starting at the position of the file pointer down to
        the end of file.
    @discussion IMPORTANT: The size of the returned data may actually be smaller than the number of 
        requested bytes, if the number of requested bytes would cause the file pointer 
        to go beyond the end of file.
        
        The file pointer is incremented by the number of bytes returned.
        
        Note that this method simply calls the getDataOfLength: method with the number 
        of bytes to read set to whatever value will move the file pointer to the end of file.
    @result An autoreleased NSData object containing the bytes from the old file pointer down to the
        end of file. nil on failure.
*/
- (NSData *)getDataToEndOfFile;
- (NSData *)getDataToEndOfFile:(NSError **)error;

- (ssize_t)read:(void *)buffer size:(size_t)size error:(NSError **)error;

/*! 
    @method writeToFile:atomically:
    @abstract Writes the entire content of the file to the specified file on disk.
    @discussion Note that this method simply calls the readDataOfLength: method with the number 
        of bytes to read set to whatever value will move the file pointer to the end of file.
        
        Note that this method simply calls NSData's writeToFile:atomically: method to write 
        the data to the disk.
    @param path Path at which the file's content should be written.
    @param atomically Set to YES to write the data to a temporary file and move it to path after.
    @result YES on success and NO on failure.
*/
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically;
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically error:(NSError **)error;

@end

