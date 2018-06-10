//
//	MPQSharedConstants.h
//	MPQKit
//
//	Created by Jean-Francois Roy on Mon Sep 30 2002.
//	Copyright (c) 2002-2007 MacStorm. All rights reserved.
//

#if !defined(MPQSharedConstants_h)
#define MPQSharedConstants_h

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
	@defined MPQ_MIN_HASH_TABLE_LENGTH
	@discussion Minimum size for an archive's hash table. Thus, the minimum number of files an archive MPQ archive can store.
*/
#define MPQ_MIN_HASH_TABLE_LENGTH 0x10

/*!
	@defined MPQ_MAX_HASH_TABLE_LENGTH
	@discussion Maximum size for a version 0 archive's hash table. Thus, the maximum number of files a version 0 MPQ archive can store.
*/
#define MPQ_MAX_HASH_TABLE_LENGTH 0x10000

/*!
	@defined MPQ_MAX_EXTENDED_HASH_TABLE_LENGTH
	@discussion Maximum size for a version 1 archive's hash table. Thus, the maximum number of files a version 1 MPQ archive can store.
*/
#define MPQ_MAX_EXTENDED_HASH_TABLE_LENGTH 0x100000

/*!
	@defined MPQ_BASE_SECTOR_SIZE
	@discussion Base sector size that needs to be shifted by MPQSectorSizeShift to compure the full sector size of an archive.
*/
#define MPQ_BASE_SECTOR_SIZE 512

#pragma mark Keys for archive information dictionaries

/*!
  @defined MPQArchiveLength
  @discussion Key for the archive size inside archive information dictionaries.
	
	The value of this key will be a NSNumber object.
*/
#define MPQArchiveSize					@"MPQArchiveSize"

/*!
  @defined MPQSectorSizeShift
  @discussion Key for the archive sector size binary shift inside archive information dictionaries.
	
	The value of this key will be a NSNumber object.
*/
#define MPQSectorSizeShift				@"MPQSectorSizeShift"

/*!
  @defined MPQNumberOfFiles
  @discussion Key for the number of valid and deleted files inside archive information dictionaries.
	
	The value of this key will be a NSNumber object.
*/
#define MPQNumberOfFiles				@"MPQNumberOfFiles"

/*!
  @defined MPQMaximumNumberOfFiles
  @discussion Key for the maximum number of files inside archive information dictionaries.
	Also used in initWithAttributes:error: to indicate the capacity of a new archive.
	
	The value of this key will be a NSNumber object.
*/
#define MPQMaximumNumberOfFiles			@"MPQMaximumNumberOfFiles"

/*!
  @defined MPQNumberOfValidFiles
  @discussion Key for the number of valid files inside archive information dictionaries.
	
	The value of this key will be a NSNumber object.
*/
#define MPQNumberOfValidFiles			@"MPQNumberOfValidFiles"

/*!
  @defined MPQArchiveOffset
  @discussion Key for the archive offset inside archive information dictionaries.
	Also used in initWithAttributes:error: to indicate the starting offset of a new archive 
	or the offset at which to start searching an MPQ header in an existing file.
	
	NSNumber objects are expected as the value of this key.
*/
#define MPQArchiveOffset				@"MPQArchiveOffset"

/*!
  @defined MPQArchivePath
  @discussion Key for the archive path inside archive information dictionaries.
	Also used in initWithAttributes:error: to indicate the location of an existing archive.
	
	The value of this key will be an NSString object.
*/
#define MPQArchivePath					@"MPQArchivePath"

/*!
	@defined MPQArchiveVersion
	@discussion Key for the archive version inside archive information dictionaries.
		Also used in initWithAttributes:error: to indicate the version of a new archive.
		
		NSNumber objects are expected as the value of this key.
*/
#define MPQArchiveVersion				@"MPQArchiveVersion"

#pragma mark Keys for file information dictionaries

/*!
  @defined MPQFileSize
  @discussion Key for the file length inside file information dictionaries.
	
	The value of this key will be a NSNumber object.
*/
#define MPQFileSize						@"MPQFileSize"

/*!
  @defined MPQFileArchiveSize
  @discussion Key for the length occupied by the file in the archive inside file information dictionaries.
	
	The value of this key will be a NSNumber object.
*/
#define MPQFileArchiveSize				@"MPQFileArchiveSize"

/*!
  @defined MPQFileArchiveOffset
  @discussion Key for the file archive offset in file information dictionaries. You must add the archive offset to this number 
	to obtain the absolute offset of the file in the archive file.
	
	The value of this key will be a NSNumber object.
*/
#define MPQFileArchiveOffset			@"MPQFileArchiveOffset"

/*!
  @defined MPQFileFlags
  @discussion Key for the file flags inside file information dictionaries. Also used in file addition parameters dictionnaries.
	See the MPQFileFlag enum page for documentation on valid flags.
	
	NSNumber objects are expected as the value of this key.
*/
#define MPQFileFlags					@"MPQFileFlags"

/*!
  @defined MPQFileLocale
  @discussion Key for the file locale inside file information dictionaries. Also used in file addition parameters dictionnaries.
	See the MPQLocale enum page for documentation on valid locales.
	
	NSNumber objects are expected as the value of this key.
*/
#define MPQFileLocale					@"MPQFileLocale"

/*!
  @defined MPQFileHashA
  @discussion Key for the file hash A inside file information dictionaries.
	
	The value of this key will be a NSNumber object.
*/
#define MPQFileHashA					@"MPQFileHashA"

/*!
  @defined MPQFileHashB
  @discussion Key for the file hash B inside file information dictionaries.
	
	The value of this key will be a NSNumber object.
*/
#define MPQFileHashB					@"MPQFileHashB"

/*!
  @defined MPQFileHashPosition
  @discussion Key for the file hash position inside file information dictionaries.
	
	The value of this key will be a NSNumber object.
*/
#define MPQFileHashPosition				@"MPQFileHashPosition"

/*!
  @defined MPQFileIndex
  @discussion Key for the file block position inside file information dictionaries.
	
	The value of this key will be a NSNumber object.
*/
#define MPQFileBlockPosition            @"MPQFileBlockPosition"

/*!
  @defined MPQFilename
  @discussion Key for the file's MPQ filename inside file information dictionaries.
	
	The value of this key will be an NSString object.
*/
#define MPQFilename						@"MPQFilename"

/*!
  @defined MPQSyntheticFilename
  @discussion Key to indicate if the MPQFilename value was synthesized by MPQKit or is the actual filename.
	
	The value of this key will be a NSNumber object wrapping a BOOL scalar.
*/
#define MPQSyntheticFilename			@"MPQSyntheticFilename"

/*!
  @defined MPQFileCanOpenWithoutFilename
  @discussion Key which can be checked to determine if a file can be opened without knowing its 
	filename inside file information dictionaries. A file may not be opened if it is 
	encrypted, its filename is not known and the encryption key cannot be brute forced.
	
	The value of this key will be a NSNumber object wrapping a BOOL scalar.
*/
#define MPQFileCanOpenWithoutFilename	@"MPQFileCanOpenWithoutFilename"

/*!
  @defined MPQFileNumberOfSectors
  @discussion Key for the number of sectors used by the file inside file information dictionaries.
	
	The value of this key will be a NSNumber object.
*/
#define MPQFileNumberOfSectors			@"MPQFileNumberOfSectors"

/*!
  @defined MPQFileEncryptionKey
  @discussion Key for the file's encryption key inside file information dictionaries. 
	Will be 0 for unencrypted file. May be 0 if the file's filename is not known.
	
	The value of this key will be a NSNumber object.
*/
#define MPQFileEncryptionKey			@"MPQFileEncryptionKey"

#pragma mark Keys for file addition parameters dictionaries

/*!
  @defined MPQCompressor
  @discussion Key for the compressor inside file addition parameters dictionaries. Note that 
	this will override the default compressor for that specific file only. See the 
	MPQCompressorFlag enum page for valid values.
	
	NSNumber objects are expected as the value of this key.
*/
#define MPQCompressor					@"MPQCompressor"

/*!
  @defined MPQCompressionQuality
  @discussion Key for the compression quality inside file addition parameters dictionaries.
	Default values are listed for each compressor in the MPQCompressor enum page.
	
	NSNumber objects are expected as the value of this key.
*/
#define MPQCompressionQuality			@"MPQCompressionQuality"

/*!
	@defined MPQOverwrite
	@discussion Key to indicate if an exiting file should be deleted inside file addition parameters dictionaries.
	
	NSNumber objects wrapping a BOOL scalar are expected as the value of this key.
*/
#define MPQOverwrite					@"MPQOverwrite"

#pragma mark Keys for archive initialization parameters dictionaries

/*!
	@defined MPQIgnoreHeaderSizeField
	@discussion Some archives have an intentionally corrupted header size field in their archive header 
		as a copy protection means. Specifying a YES value for this key will disable the header size 
		validation MPQKit normally does.
	
	NSNumber objects wrapping a BOOL scalar are expected as the value of this key.
*/
#define MPQIgnoreHeaderSizeField		@"MPQIgnoreHeaderSizeField"



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
	@constant MPQFileValid Indicates the file is valid. Automatically set by MPQKit when adding a file.
	@constant MPQFileHasSectorAdlers Indicates the file has sector adlers after the sectors.
	@constant MPQFileStopSearchMarker Indicates that searching for the file in a MPQ list should stop.
	@constant MPQFileOneSector Indicates the file is stored in a single sector.
	@constant MPQFileOffsetAdjustedKey Indicates that the file's encryption key has been offset adjusted. 
		It is not recommended to offset adjust file keys.
	@constant MPQFileEncrypted Indicates that the file is encrypted using the MPQ encryption algorithm.
	@constant MPQFileCompressed Indicates that the file is compressed using the Storm compression scheme.
	@constant MPQFileDiabloCompressed Indicates that the file is compressed using the PKWARE compressor. 
		The only reason to use this flag is to produce an archive that will be compatible with Diablo.
	@constant MPQFileFlagsMask A bit mask for valid MPQ file flags.
*/
enum {
	MPQFileValid				= 0x80000000,
	MPQFileHasSectorAdlers		= 0x04000000,
	MPQFileStopSearchMarker		= 0x02000000,
	MPQFileOneSector			= 0x01000000,
	MPQFileOffsetAdjustedKey	= 0x00020000,
	MPQFileEncrypted			= 0x00010000,
	MPQFileCompressed			= 0x00000200,
	MPQFileDiabloCompressed		= 0x00000100,
	MPQFileFlagsMask			= 0x87030300
};
typedef uint32_t MPQFileFlag;

/*!
	@typedef MPQLocale
	@abstract Valid MPQ file locale constants.
	@discussion MPQ files have a locale attribute which is used in combination with the filename to 
		identify uniquely the file inside a given archive. That means you can have multiple files 
		with the same filename but with different locales inside the same archive.
	@constant MPQNeutral The default locale.
	@constant MPQChinese Chinese (Taiwan).
	@constant MPQCzech Czech.
	@constant MPQGerman German.
	@constant MPQEnglish English (US).
	@constant MPQSpanish Spanish.
	@constant MPQFrench French.
	@constant MPQItalian Italian.
	@constant MPQJapanese Japanese.
	@constant MPQKorean Korean.
	@constant MPQDutch Dutch.
	@constant MPQPolish Polish.
	@constant MPQPortuguese Portuguese.
	@constant MPQRusssian Russsian.
	@constant MPQEnglishUK English (UK).
*/
enum {
	MPQNeutral		= 0,
	MPQChinese		= 0x404,
	MPQCzech		= 0x405,
	MPQGerman		= 0x407,
	MPQEnglish		= 0x409,
	MPQSpanish		= 0x40a,
	MPQFrench		= 0x40c,
	MPQItalian		= 0x410,
	MPQJapanese		= 0x411,
	MPQKorean		= 0x412,
	MPQDutch		= 0x413,
	MPQPolish		= 0x415,
	MPQPortuguese	= 0x416,
	MPQRusssian		= 0x419,
	MPQEnglishUK	= 0x809
};
typedef uint16_t MPQLocale;

/*!
	@typedef MPQCompressorFlag
	@abstract Valid compressor constants.
	@discussion You can use the following constants to specify which compression algorithm should be 
		used to compress a particular file, or to set the default compressor for a particular archive. 
		Note that ADPCM compression is only suitable for audio data and will destroy binary data (it is a 
		lossy compression algorithm). Files are only compressed if the MPQFileEncrypted file flag is present.
		If the MPQFileDiabloCompressed flag is present, MPQPKWARECompression is always used.
	@constant MPQHuffmanTreeCompression The standard Huffman compressor which appeared in StarCraft. There are 
		no good reasons to use this compressor other than combining it with the ADPCM compressor to replicate 
		Blizzard's compression settings in StarCraft and Diablo II for audio files.
		
		This compressor does not have a compression quality parameter.
	@constant MPQZLIBCompression The zlib compressor was added in Warcraft 3. It is the default compressor.
		
		The default compression quality for this compressor is Z_DEFAULT_COMPRESSION. Please refer to the zlib 
		documentation for more information.
	@constant MPQPKWARECompression The standard PKWARE compressor which appeared in StarCraft. You will 
		need to use this compressor for archives that will be used by StarCraft or 
		Diablo II. Note that recent versions StarCraft and Diablo II support the zlib 
		compressor as well.
		
		This compressor does not have a compression quality parameter.
	@constant MPQBZIP2Compression The bzip2 compressor was added in World of Warcraft. Offers slightly better 
		compression ratios than zlib.
		
		The compression quality corresponds to the value of the blockSize100k parameter for the BZ2_bzCompressInit 
		function. The default compression quality for this compressor is 9. Please refer to the bzip2 documentation 
		for more information.
	@constant MPQMonoADPCMCompression ADPCM compressor suitable for mono 16 bits per sample PCM audio data. Offers a 
		4:1 compression ratio. Huffman coding is historically applied on the ADPCM data to further compress the bitstream.
		
		The default compression quality for this compressor is MPQADPCMQuality4Bits (see MPQADPCMQuality for details).
	@constant MPQStereoADPCMCompression ADPCM compressor suitable for stereo 16 bits per sample PCM audio data. Offers a 
		4:1 compression ratio. Huffman coding is historically applied on the ADPCM data to further compress the bitstream.
		
		The default compression quality for this compressor is MPQADPCMQuality4Bits (see MPQADPCMQuality for details).
*/
enum {
	MPQHuffmanTreeCompression	= 0x01,
	MPQZLIBCompression			= 0x02,
	MPQPKWARECompression		= 0x08,
	MPQBZIP2Compression			= 0x10,
	MPQMonoADPCMCompression		= 0x40,
	MPQStereoADPCMCompression	= 0x80,
	MPQCompressorMask			= 0xDB
};
typedef uint8_t MPQCompressorFlag;

/*!
	@typedef MPQADPCMQuality
	@abstract ADPCM compression quality constants.
	@discussion ADPCM compression is only suitable for audio data, and doesn't really compete with 
		more advanced codecs such as MP3, AAC and Vorbis.
	@constant MPQADPCMQualityHigh High quality.
	@constant MPQADPCMQualityMedium Medium quality.
	@constant MPQADPCMQualityLow Low quality.
*/
enum {
	MPQADPCMQualityHigh		= 6,
	MPQADPCMQualityMedium	= 5,
	MPQADPCMQualityLow		= 4,
};
typedef uint8_t MPQADPCMQuality;

/*!
	@typedef MPQFileDisplacementMode
	@abstract Valid MPQFile file seeking constants.
	@constant MPQFileStart	Seeking is done with respect to the beginning of the file 
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
	MPQFileStart	= 0,
	MPQFileCurrent	= 1,
	MPQFileEnd		= 2
};
typedef uint8_t MPQFileDisplacementMode;

#if defined(USE_OPENSSL)
#import <openssl/rsa.h>
typedef RSA MPQRSA;
#elif defined(USE_CCM)
#import <CocoaCryptoMac/CocoaCryptoMac.h>
typedef CCMPublicKey MPQRSA;
#endif

#endif
