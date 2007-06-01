//
//  MPQSharedConstants.h
//  MPQKit
//
//  Created by Jean-Francois Roy on Mon Sep 30 2002.
//  Copyright (c) 2002-2007 MacStorm. All rights reserved.
//
#include <stdint.h>

/*!
  @header MPQSharedConstants.h
  This header is automatically included by MPQKit.h and provides common defines and constants 
  used by MPQKit.
*/

/*!
    @defined MPQ_MAX_PATH
    @discussion This defines the maximum length in bytes of MPQ file paths. Note that MPQs use regular ANSI C strings.
*/
#define MPQ_MAX_PATH 260

/*!
    @defined MIN_HASH_TABLE_LENGTH
    @discussion Minimum size for an archive's hash table. Thus, the minimum number of files an archive MPQ archive can store.
*/
#define MIN_HASH_TABLE_LENGTH 0x10

/*!
    @defined MAX_HASH_TABLE_LENGTH
    @discussion Maximum size for a version 0 archive's hash table. Thus, the maximum number of files a version 0 MPQ archive can store.
*/
#define MAX_HASH_TABLE_LENGTH 0x10000

/*!
    @defined MAX_EXTENDED_HASH_TABLE_LENGTH
    @discussion Maximum size for a version 1 archive's hash table. Thus, the maximum number of files a version 1 MPQ archive can store.
*/
#define MAX_EXTENDED_HASH_TABLE_LENGTH 0x100000

#pragma mark Keys for archive information dictionaries

/*!
  @defined MPQArchiveLength
  @discussion Key for the archive size inside archive information dictionaries.
    
    The value of this key will be an NSNumber object.
*/
#define MPQArchiveSize                  @"MPQArchiveSize"

/*!
  @defined MPQSectorSizeShift
  @discussion Key for the archive sector size binary shift inside archive information dictionaries.
    
    The value of this key will be an NSNumber object.
*/
#define MPQSectorSizeShift              @"MPQSectorSizeShift"

/*!
  @defined MPQNumberOfFiles
  @discussion Key for the number of normal and delete files inside archive information dictionaries.
    
    The value of this key will be an NSNumber object.
*/
#define MPQNumberOfFiles                @"MPQNumberOfFiles"

/*!
  @defined MPQMaximumNumberOfFiles
  @discussion Key for the maximum number of files inside archive information dictionaries.
    Also used in initWithAttributes:error: to indicate the capacity of a new archive.
    
    The value of this key will be an NSNumber object.
*/
#define MPQMaximumNumberOfFiles         @"MPQMaximumNumberOfFiles"

/*!
  @defined MPQNumberOfValidFiles
  @discussion Key for the number of valid files inside archive information dictionaries.
    
    The value of this key will be an NSNumber object.
*/
#define MPQNumberOfValidFiles           @"MPQNumberOfValidFiles"

/*!
  @defined MPQArchiveOffset
  @discussion Key for the archive offset inside archive information dictionaries.
    Also used in initWithAttributes:error: to indicate the starting offset of a new archive.
    
    The value of this key will be an NSNumber object.
*/
#define MPQArchiveOffset                @"MPQArchiveOffset"

/*!
  @defined MPQArchivePath
  @discussion Key for the archive path inside archive information dictionaries.
    Also used in initWithAttributes:error: to indicate the location of an existing archive.
    
    The value of this key will be an NSString object.
*/
#define MPQArchivePath                  @"MPQArchivePath"

/*!
    @defined MPQArchiveVersion
    @discussion Key for the archive version inside archive information dictionaries.
        Also used in initWithAttributes:error: to indicate the version of a new archive.
        
        NSNumber objects are expected as the value of this key.
*/
#define MPQArchiveVersion               @"MPQArchiveVersion"

#pragma mark Keys for file information dictionaries

/*!
  @defined MPQFileSize
  @discussion Key for the file length inside file information dictionaries.
    
    The value of this key will be an NSNumber object.
*/
#define MPQFileSize                     @"MPQFileSize"

/*!
  @defined MPQFileArchiveSize
  @discussion Key for the length occupied by the file in the archive inside file information dictionaries.
    
    The value of this key will be an NSNumber object.
*/
#define MPQFileArchiveSize              @"MPQFileArchiveSize"

/*!
  @defined MPQFileFlags
  @discussion Key for the file flags inside file information dictionaries. Also used in file addition parameters dictionnaries.
    See the MPQFileFlag enum page for documentation on valid flags.
    
    NSNumber objects are expected as the value of this key.
*/
#define MPQFileFlags                    @"MPQFileFlags"

/*!
  @defined MPQFileLocale
  @discussion Key for the file locale inside file information dictionaries. Also used in file addition parameters dictionnaries.
    See the MPQLocale enum page for documentation on valid locales.
    
    NSNumber objects are expected as the value of this key.
*/
#define MPQFileLocale                   @"MPQFileLocale"

/*!
  @defined MPQFileHashA
  @discussion Key for the file hash A inside file information dictionaries.
    
    The value of this key will be an NSNumber object.
*/
#define MPQFileHashA                    @"MPQFileHashA"

/*!
  @defined MPQFileHashB
  @discussion Key for the file hash B inside file information dictionaries.
    
    The value of this key will be an NSNumber object.
*/
#define MPQFileHashB                    @"MPQFileHashB"

/*!
  @defined MPQFileHashPosition
  @discussion Key for the file hash position inside file information dictionaries.
    
    The value of this key will be an NSNumber object.
*/
#define MPQFileHashPosition             @"MPQFileHashPosition"

/*!
  @defined MPQFilename
  @discussion Key for the file MPQ path inside file information dictionaries.
    
    The value of this key will be an NSString object.
*/
#define MPQFilename                     @"MPQFilename"

/*!
  @defined MPQFileCanOpenWithoutFilename
  @discussion Boolean key which can be checked to know if a file can be opened without knowing its filename. 
    A file may not be opened if it is encrypted and its name is not known.
    
    The value of this key will be an NSNumber object.
*/
#define MPQFileCanOpenWithoutFilename   @"MPQFileCanOpenWithoutFilename"

#pragma mark Keys for file addition parameters dictionaries

/*!
  @defined MPQCompressor
  @discussion Key for the compressor inside file addition parameters dictionaries. Note that 
    this will override the default compressor for that specific file only. See the 
    MPQCompressorFlag enum page for valid values.
    
    NSNumber objects are expected as the value of this key.
*/
#define MPQCompressor                   @"MPQCompressor"

/*!
  @defined MPQCompressionQuality
  @discussion Key for the compression quality inside file addition parameters dictionaries.
    Default values are listed for each compressor in the MPQCompressor enum page.
    
    NSNumber objects are expected as the value of this key.
*/
#define MPQCompressionQuality           @"MPQCompressionQuality"

/*!
    @defined MPQOverwrite
    @discussion Key to indicate if an exiting file should be deleted 
        inside file addition parameters dictionaries.
    
    NSNumber objects are expected as the value of this key.
*/
#define MPQOverwrite                    @"MPQOverwrite"

#pragma mark Keys for archive initialization parameters dictionaries



#pragma mark Flags

/*!
    @typedef MPQVersion
    @abstract High-level constants for known MPQ versions.
    @constant MPQOriginalVersion The original archive format.
    @constant MPQExtendedVersion The extended archive format.
*/
enum {
    MPQOriginalVersion = 0,
    MPQExtendedVersion = 1,
};
typedef uint16_t MPQVersion;

/*!
    @typedef MPQFileFlag
    @abstract Valid MPQ file flag constants.
    @constant MPQFileValid Marks the file as valid. Automatically added by the framework 
        when a new file is added.
    @constant MPQFileHasMetadata Indicates the file has associated metadata.
    @constant MPQFileOneSector File is compressed in a single large sector.
    @constant MPQFileOffsetAdjustedKey Indicates that this file's encryption key has been offset adjusted. 
        As such, that file's name will be required for rename and compaction operations because if it 
        needs to be moved inside the MPQ archive, it will have to be recompressed and/or reencrypted. 
        It is not recommended to offset adjust file keys.
    @constant MPQFileEncrypted Indicates that the file either should be encrypted upon addition or is 
        encrypted for existing files.
    @constant MPQFileCompressed Indicates that the file either should be compressed upon addition or is 
        compressed for existing files. Compression will use the default compressor and compression 
        quality for the selected compressor unless they are overridden by addition parameters.
    @constant MPQFileDiabloCompressed This flag indicates the file should be or is compressed using PKWARE 
        compression. When this flag is used for addition, the PKWARE compressor will be used for 
        the file regardless of addition parameters or the currently set default compressor. 
        The only reason to use this flag is to produce an archive that will be 
        compatible with Diablo.
    @constant MPQFileFlagsMask A bit mask for valid MPQ file flags.
*/
enum {
    MPQFileValid                = 0x80000000,
    MPQFileHasMetadata          = 0x04000000,
    MPQFileDummy                = 0x02000000,
    MPQFileOneSector            = 0x01000000,
    MPQFileOffsetAdjustedKey    = 0x00020000,
    MPQFileEncrypted            = 0x00010000,
    MPQFileCompressed           = 0x00000200,
    MPQFileDiabloCompressed     = 0x00000100,
    MPQFileFlagsMask            = 0x87030300
};
typedef uint32_t MPQFileFlag;

/*!
    @typedef MPQLocale
    @abstract Valid MPQ file locale constants.
    @discussion MPQ files have a locale attribute which is used in combination with the file path to 
        identify uniquely the file inside a given archive. That means you can have multiple files 
        with the same path and name but with a different locale inside the same archive. The use of 
        locale values seems deprecated by Blizzard.
    @constant MPQNeutral  The default locale. Should be used for any non-localizable files, such as 
        textures, binary tables, executables, etc.
    @constant MPQChinese  Chinese (Taiwan) locale constant.
    @constant MPQCzech  Czech locale constant.
    @constant MPQGerman  German locale constant.
    @constant MPQEnglish  English locale constant.
    @constant MPQSpanish  Spanish locale constant.
    @constant MPQFrench  French locale constant.
    @constant MPQItalian  Italian locale constant.
    @constant MPQJapanese  Japanese locale constant.
    @constant MPQKorean  Korean locale constant.
    @constant MPQDutch  Dutch locale constant.
    @constant MPQPolish  Polish locale constant.
    @constant MPQPortuguese  Portuguese locale constant.
    @constant MPQRusssian  Russsian locale constant.
    @constant MPQEnglishUK  English (UK) locale constant.
*/
enum {
    MPQNeutral      = 0,
    MPQChinese      = 0x404,
    MPQCzech        = 0x405,
    MPQGerman       = 0x407,
    MPQEnglish      = 0x409,
    MPQSpanish      = 0x40a,
    MPQFrench       = 0x40c,
    MPQItalian      = 0x410,
    MPQJapanese     = 0x411,
    MPQKorean       = 0x412,
    MPQDutch        = 0x413,
    MPQPolish       = 0x415,
    MPQPortuguese   = 0x416,
    MPQRusssian     = 0x419,
    MPQEnglishUK    = 0x809
};
typedef uint16_t MPQLocale;

/*!
    @typedef MPQCompressorFlag
    @abstract Valid compressor constants.
    @discussion You can use the following constants to specify which compression algorithm should be 
        used to compress a particular file, or to set the default compressor for a particular archive. 
        Note that ADPCM compression is only suitable for audio data and will destroy binary data (it is a 
        lossy compression algorithm).
    @constant MPQPKWARECompression The standard PKWARE compressor which appeared in Starcraft. You will 
        need to use this compressor for new files in archives that will be used by Starcraft or 
        Diablo II. Note that the Mac OS X version of Starcraft and Diablo II support the zlib 
        compressor as well.
        
        This compressor does not have a compression quality parameter.
    @constant MPQStereoADPCMCompression ADPCM compressor suitable for audio data. Offers a 4:1 compression ratio. 
        Huffman coding is applied on the ADPCM data to further compress the bitstream.
        
        The default compression quality for this compressor is MPQADPCMQualityHigh (see MPQADPCMQuality for details).
    @constant MPQBZIP2Compression The bzip2 compressor was added in World of Warcraft. Offers slightly better compression ratios than zlib.
        
        The default compression quality for this compressor is 0. Please refer to the bzip2 documentation for more information.
    @constant MPQZLIBCompression The zlib compressor was added in Warcraft 3. It is the default compressor.
        
        The default compression quality for this compressor is Z_DEFAULT_COMPRESSION. Please refer to the zlib documentation for more information.
*/
enum {
    MPQPKWARECompression        = 0x08,
    MPQStereoADPCMCompression   = 0x81,
    MPQBZIP2Compression         = 0x10, 
    MPQZLIBCompression          = 0x02
};
typedef uint8_t MPQCompressorFlag;

/*!
    @typedef MPQADPCMQuality
    @abstract ADPCM compression quality constants.
    @discussion ADPCM compression is only suitable for audio data, and doesn't really compete with 
        more advanced codecs such as MP3, AAC and Vorbis.
    @constant MPQADPCMQuality4Bits Uses 4 bits per sample.
    @constant MPQADPCMQuality2Bits Uses 2 bits per sample.
*/
enum {
    MPQADPCMQuality4Bits    = 4,
    MPQADPCMQuality2Bits    = 2
};
typedef uint8_t MPQADPCMQuality;

/*!
    @typedef MPQFileDisplacementMode
    @abstract Valid MPQFile file seeking constants.
    @constant MPQFileStart  Seeking is done with respect to the beginning of the file 
        and toward the end of file. In effect, this makes nDistanceToMove an absolute 
        file offset to seek to.
    @constant MPQFileCurrent  Seeking is done with respect to the current file pointer 
        and toward the end of file. If nDistanceToMove will move the file pointer 
        beyond the end of file, the file pointer is moved to the end of file.
    @constant MPQFileEnd  Seeking is done with respect to the end of file and toward 
        the beginning of the file. If nDistanceToMove will move the file pointer 
        to a negative position, the file pointer is moved to the beginning of the 
        file.
*/
enum {
    MPQFileStart    = 0,
    MPQFileCurrent  = 1,
    MPQFileEnd      = 2
};
typedef uint8_t MPQFileDisplacementMode;
