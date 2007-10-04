//
//  MPQArchive.h
//  MPQKit
//
//  Created by Jean-Francois Roy on Tue Oct 01 2002.
//  Copyright (c) 2002-2007 MacStorm. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <MPQKit/MPQSharedConstants.h>
#import <MPQKit/MPQDataSource.h>

#import <openssl/rsa.h>

/*!
  @header MPQArchive.h
  This header is automatically included by MPQKit.h and provides the definition of the class 
  MPQArchive.
*/

@class MPQFile;

#pragma options align=packed
struct mpq_header {
    uint32_t mpq_magic;
    uint32_t header_size;
    uint32_t archive_size;
    uint16_t version;
    uint16_t sector_size_shift;
    uint32_t hash_table_offset;
    uint32_t block_table_offset;
    uint32_t hash_table_length;
    uint32_t block_table_length;
};
typedef struct mpq_header mpq_header_t;

struct mpq_extended_header {
    uint64_t extended_block_offset_table_offset;
    uint16_t hash_table_offset_high;
    uint16_t block_table_offset_high;
};
typedef struct mpq_extended_header mpq_extended_header_t;

struct mpq_hash_table_entry {
    uint32_t hash_a;
    uint32_t hash_b;
    uint16_t locale;
    uint16_t platform;
    uint32_t block_table_index;
};
typedef struct mpq_hash_table_entry mpq_hash_table_entry_t;

struct mpq_block_table_entry {
    uint32_t offset;
    uint32_t archived_size;
    uint32_t size;
    uint32_t flags;
};
typedef struct mpq_block_table_entry mpq_block_table_entry_t;

struct mpq_extended_block_offset_table_entry {
    uint16_t offset_high;
};
typedef struct mpq_extended_block_offset_table_entry mpq_extended_block_offset_table_entry_t;

struct mpq_attributes_header {
    uint32_t magic;
    uint32_t attributes;
};
typedef struct mpq_attributes_header mpq_attributes_header_t;

#define MPQ_OLD_SIGNATURE_KEY_SIZE 512
struct mpq_old_signature {
	uint32_t unknown0;
	uint32_t unknown4;
	uint8_t signature[MPQ_OLD_SIGNATURE_KEY_SIZE / 8];
};
typedef struct mpq_old_signature mpq_old_signature_t;

struct mpq_shunt {
    uint32_t shunt_magic;
    uint32_t unknown04;
    uint32_t mpq_header_offset;
};
typedef struct mpq_shunt mpq_shunt_t;
#pragma options align=reset

// Internal types and structures for defered operations
typedef enum {
    MPQDOAdd = 1,
    MPQDODelete,
    MPQDORename,
} MPQDeferredOperationType;

struct mpq_deferred_operation_file_context {
    uint32_t hash_position;
    mpq_hash_table_entry_t hash_entry;
    mpq_block_table_entry_t block_entry;
    off_t block_offset;
    uint32_t encryption_key;
    NSString *filename;
};
typedef struct mpq_deferred_operation_file_context mpq_deferred_operation_file_context_t;

struct mpq_deferred_operation {
    MPQDeferredOperationType type;
    mpq_deferred_operation_file_context_t primary_file_context;
    void *context;
    struct mpq_deferred_operation *previous;
};
typedef struct mpq_deferred_operation mpq_deferred_operation_t;

struct mpq_deferred_operation_add_context {
    MPQDataSourceProxy *dataSourceProxy;
    uint32_t compressor;
    int32_t compression_quality;
};
typedef struct mpq_deferred_operation_add_context mpq_deferred_operation_add_context_t;

struct mpq_deferred_operation_delete_context {
};
typedef struct mpq_deferred_operation_delete_context mpq_deferred_operation_delete_context_t;

/*!
    @class MPQArchive
    @abstract MPQArchive is the principal class of MPQKit and represents an MPQ archive document.
    @discussion MPQArchive is the principal class of MPQKit and represents an MPQ archive
        document. As such, there is a one-to-one relationship between MPQArchive instances and MPQ archives 
        on disk.
        
        You may create a new MPQArchive instance either with only a file limit parameter, 
        and provide the location of the archive on disk at save time, or create a new MPQArchive 
        with a path and a file limit parameter, in which case the archive file is created right away.
        The first method better matches the Cocoa document model.
        
        Unlike most other MPQ libraries, MPQArchive has deferred operations, meaning the archive on disk 
        is not modified until you explicitly do so. Again, this behavior better matches the Cocoa document model.
        
        It is important to note that MPQArchive is NOT THREAD SAFE, and as such all access to a particular MPQArchive 
        instance should be protected by a lock in applications where multiple threads may access the same MPQArchive 
        instance.
        
        In addition, MPQArchive makes no check at all to see if other MPQArchive instances exist for a particular 
        archive file. There are obvious coherency issues with having multiple MPQArchive instances refer to the same 
        archive on disk, unless all instances are read-only.
*/
@interface MPQArchive : NSObject {
    BOOL is_modified;
    BOOL is_read_only;
    BOOL save_listfile;
    
    int archive_fd;
    NSString *archive_path;

    off_t archive_offset;
    off_t archive_write_offset;
    off_t archive_size;
    
    mpq_header_t header;
    mpq_extended_header_t extended_header;
    
    uint32_t full_sector_size;
    
    off_t hash_table_offset;
    off_t block_table_offset;
    
    mpq_hash_table_entry_t *hash_table;
    mpq_block_table_entry_t *block_table;
    
    off_t *block_offset_table;
    char **filename_table;
    NSDictionary **file_info_cache;
    
    void *attributes_data;
    uint32_t attributes_data_size;
    
    mpq_hash_table_entry_t *weak_signature_hash_entry;
    uint8_t *strong_signature;
    
    uint32_t open_file_count;
    uint32_t *open_file_count_table;
    
    void *read_buffer;
    void *compression_buffer;
    
    mpq_deferred_operation_t *last_operation;
    mpq_deferred_operation_t **operation_hash_table;
    uint32_t deferred_operations_count;
    
    uint32_t **sector_tables_cache;
    uint32_t *encryption_keys_cache;
    
    uint32_t default_compressor;
    
    id delegate;
}

/*! 
    @method localeName:
    @abstract Returns a string representing the given locale code.
    @discussion Returns a string such as "English", "French", etc. for a given locale code.
    @param locale The locale code. Must be a valid locale code.
    @result Returns an NSString object, or nil if the locale code is invalid.
*/
+ (NSString *)localeName:(MPQLocale)locale;
+ (NSLocale *)localeForMPQLocale:(MPQLocale)locale;

#pragma mark initialization

/*! 
    @method archiveWithFileLimit:
    @abstract Creates and returns a new autoreleased MPQArchive instance initialized with the given
        file limit. No file is created on disk.
    @discussion This method calls initWithFileLimit:.
    @param limit An integer indicating the maximum number of files the new archive may contain. If you pass 0, 
        MPQArchive will set this parameter to a default value of 0x400. The file limit must be a power of 2 and will 
        automatically be rounded off to one, so you may safely pass any integer. Finally, if the limit is too 
        low or too high, MPQKit will adjust upward or downward as needed.
    @result Returns the newly initialized MPQArchive object or nil on error.
*/
+ (id)archiveWithFileLimit:(uint32_t)limit;
+ (id)archiveWithFileLimit:(uint32_t)limit error:(NSError **)error;

/*! 
    @method archiveWithPath:
    @abstract Creates and returns a new autoreleased MPQArchive instance initialized with the archive at the specified path.
    @discussion This method calls initWithPath:.
    @param path The POSIX path to the archive. Must be a fully expanded path. Must not be nil.
    @result Returns the newly initialized MPQArchive object or nil on error.
*/
+ (id)archiveWithPath:(NSString *)path;
+ (id)archiveWithPath:(NSString *)path error:(NSError **)error;

/*!
    @method archiveWithAttributes:error:
    @abstract Creates and returns a new autoreleased MPQArchive instance initialized with the provided attributes.
    @discussion For documentation on valid attributes, please see the initWithAttributes:error: method.
    @param attributes Dictionary of attributes. Cannot be nil.
    @param error Optional pointer to a NSError *.
    @result Returns the newly initialized MPQArchive object or nil on error.
*/
+ (id)archiveWithAttributes:(NSDictionary *)attributes error:(NSError **)error;

/*!
    @method initWithAttributes:error:
    @abstract Creates and returns a new MPQArchive instance initialized with the provided attributes.
    @discussion This method is the designated initializer of MPQArchive.
        
        If the attributes dictionary contains a value for the MPQArchivePath key, then all 
        other attributes are ignored and MPQKit will try to initialize the instance from 
        the file at the provided path.
        
        Otherwise, a new archive will be created with the following default options, 
        which may be overridden by various attributes.
        
        * Maximum number of files: 1024
        * Archive version: 0
        * Archive offset: 0
        
        To change the file limit, specify a value for the MPQMaximumNumberOfFiles key. To 
        change the version, specifiy a value for the MPQArchiveVersion key. To change the 
        offset, specify a value for the MPQArchiveOffset key.
        
        MPQKit supports version 0 archives (the original format) and version 1
        archives (or extended archives) that were introduced in Burning Crusade. MPQVersion 
        constants are provided for known versions as well.
    @param attributes Dictionary of attributes. Cannot be nil.
    @param error Optional pointer to a NSError *.
    @result Returns the newly initialized MPQArchive object or nil on error.
*/
- (id)initWithAttributes:(NSDictionary *)attributes error:(NSError **)error;

/*! 
    @method initWithFileLimit:
    @abstract Creates and returns a new MPQArchive instance initialized with the given
        file limit. No file is created on disk.
    @discussion Some operations that require an archive file to exist may fail until the instance's 
		writeToFile:atomically: method is used. For compatibility reasons, this method creates 
        version 0 archives. Calls initWithAttributes:error: with suitable attributes.
    @param limit An integer indicating the maximum number of files the new archive may contain. If you pass 0, 
        MPQArchive will set this parameter to a default value of 0x400. The file limit must be a power of 2 and will 
        automatically be rounded off to one, so you may safely pass any integer. Finally, if the limit is too 
        low or too high, MPQKit will adjust upward or downward as needed.
    @result Returns the newly initialized MPQArchive object or nil on error.
*/
- (id)initWithFileLimit:(uint32_t)limit;
- (id)initWithFileLimit:(uint32_t)limit error:(NSError **)error;

/*! 
    @method initWithPath:
    @abstract Creates and returns a new MPQArchive instance initialized with the archive at the specified path.
    @discussion Depending on file system permissions and the storage medium of the file, the archive may be read-only. 
         Calls initWithAttributes:error: with suitable attributes.
    @param path The POSIX path to the archive. Must be a fully expanded path. Must not be nil.
    @result Returns the newly initialized MPQArchive object or nil on error.
*/
- (id)initWithPath:(NSString *)path;
- (id)initWithPath:(NSString *)path error:(NSError **)error;

#pragma mark delegate

/*!
    @method delegate
    @abstract Returns the current delegate.
    @discussion MPQArchive principally notifies its delegate about operations that are about to be performed or 
        that finished performing, and also to control operations (allow or disallow).
    @result The delegate or nil.
*/
- (id)delegate;

/*!
    @method setDelegate:
    @abstract Set the archive's delegate.
    @discussion The delegate is not retained.
*/
- (void)setDelegate:(id)anObject;

#pragma mark archive information

/*! 
    @method archiveInfo
    @abstract Returns the information dictionary for the MPQ archive.
    @discussion Archive information dictionaries will always contain the following keys:
        
        * MPQArchiveSize: The size of the archive on the disk in bytes as an integer.
        * MPQSectorSizeShift: The full sector size binary shift as an integer.
        * MPQNumberOfFiles: The number of valid and deleted files in the archive as an integer.
        * MPQMaximumNumberOfFiles: The maximum number of files the archive may contain as an integer.
        * MPQNumberOfValidFiles: The number of valid files in the archive as an integer.
        * MPQArchiveOffset: MPQ archives may be embedded in other files at 512 bytes boundaries.
        * MPQArchiveVersion: The version of the archive.
        This is the offset of the MPQ archive within its container file in bytes as an integer.
    @result An NSDictionary object containing the archive's information on success or nil on failure.
*/
- (NSDictionary *)archiveInfo;

/*! 
    @method path
    @abstract Returns the path of the archive associated with the instance.
    @discussion May be nil if the instance was initialized with archiveWithFileLimit: or 
        initWithFileLimit: and the archive has never been saved yet.
    @result Returns the absolute path of the archive as an integer.
*/
- (NSString *)path;

/*! 
    @method modified
    @abstract Returns the current document state of the archive.
    @discussion Will always return NO if the archive is read-only. When an archive was just initialized 
		from a file, should always return NO. When an archive was just initialized in memory, will always 
		return YES.
    @result Returns YES if the archive has been modified and NO if it has not.
*/
- (BOOL)modified;

/*! 
    @method readOnly
    @abstract Returns the read-only state of the archive.
    @discussion Returns NO for archives initialized in memory. This may return YES for existing archives 
		depending on what permissions the archive file has and on what type of media it is stored.
    @result Returns YES if the archive is read-only and NO if it is read-write.
*/
- (BOOL)readOnly;

/*! 
    @method openFileCount
    @abstract Returns the number of open archive files.
    @discussion There must be no open files in order to save the archive to disk.
    @result Returns the number of open MPQ files as an integer.
*/
- (uint32_t)openFileCount;

/*! 
    @method openFileCountWithPosition:
    @abstract Returns the number of MPQFile instances for a given archive file.
    @discussion There must be no open files in order to save the archive to disk.
    @param position The hash table position of the desired file. May be obtained 
        from the file information methods of MPQArchive and MPQFile.
    @result Returns the number of MPQFile instances for a given archive file.
*/
- (uint32_t)openFileCountWithPosition:(uint32_t)position;

/*! 
    @method fileCount
    @abstract Returns the number of valid and deleted files inside the archive.
    @discussion You may calculate the number of deleted files by substracting this number 
        with the result of validFileCount.
    @result Returns the number of used and deleted files inside the archive as an integer.
*/
- (uint32_t)fileCount;

/*! 
    @method validFileCount
    @abstract Returns the number of valid files inside the archive.
    @discussion This includes every valid file, even if the filename is unknown.
    @result Returns the number of valid files inside the archive as an integer.
*/
- (uint32_t)validFileCount;

/*! 
    @method maximumNumberOfFiles
    @abstract Returns the maximum number of files the archive may contain.
    @discussion There is no way to increase this limit once an archive is created. Thus, if an archive is full, 
        you may have to delete some files or create a bigger archive and copy every file from one to the other, which you 
        may not be able to do if you don't know the file name of every file. This limit is inherent to the MPQ format.
    @result Returns the maximum number of files the archive may contain as an integer.
*/
- (uint32_t)maximumNumberOfFiles;

#pragma mark operations

/*
    @method operationCount
    @abstract Returns the number of operations that will be performed when the archive is written to disk.
    @discussion You can expect to receive this many delegate messages reporting what
        operation MPQKit is about to do or just completed when writeToFile:atomically: is called.
    @result Returns the number of operations as an integer.
*/
- (uint32_t)operationCount;

- (BOOL)undoLastOperation:(NSError **)error;

#pragma mark digital signing

/*!
	@method computeWeakSignatureDigest
	@abstract Computes the weak signature digest of the archive.
	@discussion This method will return nil if the archive does not have a weak signature or if the instance 
		was initialized in memory and has not been written to disk yet.
        
        The weak signature digest cannot be computed until the archive contains a (signature) file whose length 
        is exactly 72 bytes.
		
		Note that this method may take some time for large archives, since it computes a whole archive MD5 checksum.
    @param error Optional pointer to a NSError *.
	@result Returns the weak archive digest or nil on error.
*/
- (NSData *)computeWeakSignatureDigest:(NSError **)error;

/*!
	@method verifyBlizzardWeakSignature:
	@abstract Returns YES if the archive has been weakly signed using Blizzard's weak RSA key and the signature 
		matches the archive's weak digest. Otherwise returns NO.
	@discussion TBW
    @param isSigned If you want to distinguish between an invalid signature and no signature, you can pass a BOOL pointer. 
        Otherwise, set to NULL.
    @param error Optional pointer to a NSError *.
	@result Returns YES if the archive was weakly signed by Blizzard and the signature is valid, NO otherwise.
*/
- (BOOL)verifyBlizzardWeakSignature:(BOOL *)isSigned error:(NSError **)error;

/*!
	@method computeStrongSignatureDigestFrom:size:tail:
	@abstract Computes the strong signature digest of the archive.
	@discussion This method will return nil if the instance resides entirely in memory, or in other words if the 
        instance is not backed by an archive on disk.
        
        The digestOffset parameter should be the archive offset for a normal strong digest, and 0 for 
        the strong digest of a Warcraft 3 map (since the signature includes the map header).
        
        The digestSize parameter should be the archive size for a normal strong digest, and the sum of the
        archive offset anf size for the strong digest of a Warcraft 3 map (since the signature includes the map header).
        
        The archive offset can be obtained from the archiveInfo dictionary using the MPQArchiveOffset key. 
        The archive offset can be obtained from the archiveInfo dictionary using the MPQArchiveSize key.
        
        digestTail can be used for special signatures, such as Macintosh World of Warcraft patch or Warcraft 3 map 
        signatures.
		
		Note that this method may take some time for large archives, since it computes a whole archive SHA1 checksum.
    @param digestOffset The offset in the archive file at which to begin the digest.
    @param digestSize The number of bytes from the archive file to digest.
    @param digestTail Data to be appended to the digest once the archive file has been digested but prior to closing the digest. Can be nil if not needed.
    @param error Optional pointer to a NSError *.
	@result Returns the strong archive digest or nil on error.
*/
- (NSData *)computeStrongSignatureDigestFrom:(off_t)digestOffset size:(off_t)digestSize tail:(NSData *)digestTail error:(NSError **)error;

/*!
    @method hasStrongSignature
    @abstract Returns whether or not the archive has a strong signature.
    @discussion This method should be called before computing the strong digital signature digest of the archive 
        if you intend on verifying that digest to avoid a lenghty computation when the archive is not signed.
*/
- (BOOL)hasStrongSignature;

/*!
    @method verifyStrongSignature:isSigned:error:
    @abstract Verifies the archive's strong signature against a particular RSA public key.
    @discussion This method verifies that the archive's strong digital signature was
        created with the private RSA key associated with the given public RSA key.
        
        This method is not suitable to verify Warcraft 3 map strong signatures. For Blizzard Entertainment 
        signatures, there are convenience methods available that make use of MPQKit's built-in public keys 
        and take care of computing an appropriate digest.
    @param key The public RSA key to verify against.
    @param digest The strong digital signature digest to verify against.
    @param error Optional pointer to a NSError *.
    @result Returns YES if the archive was signed with the provided public key's associated private key, NO otherwise.
*/
- (BOOL)verifyStrongSignatureWithKey:(RSA *)key digest:(NSData *)digest error:(NSError **)error;

- (BOOL)verifyBlizzardStrongSignature:(NSError **)error;
- (BOOL)verifyWoWSurveySignature:(NSError **)error;
- (BOOL)verifyWoWMacPatchSignature:(NSError **)error;
- (BOOL)verifyWarcraft3MapSignature:(NSError **)error;
- (BOOL)verifyStarcraftMapSignature:(NSError **)error;

#pragma mark options

/*! 
    @method storesListfile
    @abstract Returns whether or not the instance will save the list of files inside the archive in
        the internal MPQ listfile at save time.
    @discussion Each MPQArchive instance has a list of the paths of the files inside its associated 
        MPQ archive. Because MPQs don't inherently store the list of files they contain, MPQ editors have gone 
        around this by manually managing a file inside MPQ archives called (listfile).
        
        There are several advantages to having the path of a file, such as being able to re-compress it and/or re-encrypt it in 
        operations such as compaction. Without the path, it would be quasi-impossible to perform those operations. 
        Note that whenever you try to open a file of the archive, the MPQArchive instance will add the path 
        you used to open the file to its internal list of files if the file is actually found. You may also 
        add external listfiles (available from the web) to the instance's internal list of files using 
        the addListfileToFileList: and addArrayToFileList: methods.
        
        The default behavior is to save the listfile at save time.
    @result Returns YES if the listfile will be added to the archive or NO if it will not.
*/
- (BOOL)storesListfile;

/*! 
    @method setStoresListfile:
    @abstract Set whether or not the instance will save the list of files inside the archive in
        the internal MPQ listfile at save time.
    @discussion Each MPQArchive instance has a list of the paths of the files inside its associated 
        MPQ archive. Because MPQs don't inherently store the list of files they contain, MPQ editors have gone 
        around this by manually managing a file inside MPQ archives called (listfile).
        
        There are several advantages to having the path of a file, such as being able to re-compress it and/or re-encrypt it in 
        operations such as compaction. Without the path, it would be quasi-impossible to perform those operations. 
        Note that whenever you try to open a file of the archive, the MPQArchive instance will add the path 
        you used to open the file to its internal list of files if the file is actually found. You may also 
        add external listfiles (available from the web) to the instance's internal list of files using 
        the addListfileToFileList: and addArrayToFileList: methods.
        
        It is recommended to save the listfile.
    @param store YES to make the instance save the listfile at save time or NO to prevent it from doing so.
*/
- (void)setStoresListfile:(BOOL)store;

/*! 
    @method defaultCompressor
    @abstract Returns the current default compressor.
    @discussion The default default compressor is zlib.
    @result A MPQCompressorFlag constant. Please refer to the MPQCompressorFlag documentation for more information.
*/
- (MPQCompressorFlag)defaultCompressor;

/*! 
    @method setDefaultCompressor:
    @abstract Sets the default compressor of the instance.
    @discussion For details on the available compressors, please refer to the MPQCompressorFlag documentation. Note 
        that as a precaution, the ADPCM compressors cannot be set as the default because they are lossy.
    @param compressor A MPQCompressorFlag constant.
    @result YES on sucess or NO on failure.
*/
- (BOOL)setDefaultCompressor:(MPQCompressorFlag)compressor;

#pragma mark file list

/*! 
    @method loadInternalListfile:
    @abstract Loads the internal MPQ listfile into the instance's own internal list of files. Helps to get valid file
        paths when using the file information routines.
    @discussion Each MPQArchive instance has a list of the files inside its archive. Because MPQs don't inherently 
        store the list of files they contain, Blizzard has gone around this by manually managing a file inside 
        archives called (listfile) which stores the files stored in the archive, one entry per line.
        
        There are several advantages to having the path of a file, such as being able to re-compress it and/or re-encrypt it in 
        operations such as compaction. Without the path, it would be quasi-impossible to perform those operations. 
        Note that whenever you try to open a file of the archive, the MPQArchive instance will add the path 
        you used to open the file to its internal list of files if the file is actually found. You may also 
        add external file lists (available from the web) to the instance's internal file list using 
        the addListfileToFileList: and addArrayToFileList: methods.
        
        This method attemps to read the archive's internal file list and add its content to the instance's internal list 
        of files. MPQArchive will make sure each entry actually exists before adding it to the list.
    @param error Optional pointer to a NSError *.
    @result YES on sucess or NO on failure.
*/
- (BOOL)loadInternalListfile:(NSError **)error;

/*! 
    @method addArrayToFileList:
    @abstract Adds a list of paths to the instance's internal list of files.
    @discussion See the discussion on loadInternalListfile for more details on file lists.
        This method attemps to add each entry of the provided array to the instance's internal list 
        of files. MPQArchive will make sure each entry actually exists inside the archive 
        before adding it to the file list.
    @param listfile A NSArray containing file paths. Note that the path separator MUST BE \, and not /.
    @result YES on sucess or NO on failure.
*/
- (BOOL)addArrayToFileList:(NSArray *)listfile;
- (BOOL)addArrayToFileList:(NSArray *)listfile error:(NSError **)error;

/*! 
    @method addContentsOfFileToFileList:
    @abstract Adds the entries of an external list of files to the instance's internal list of files.
    @discussion See the discussion on loadInternalListfile for more details on file lists.
        
        This method attemps to add each line of the provided text file to the instance's internal list
        of files. MPQArchive will make sure each entry actually exists before adding it to the list.
    @param path System path to the file.
    @result YES on sucess or NO on failure.
*/
- (BOOL)addContentsOfFileToFileList:(NSString *)path;
- (BOOL)addContentsOfFileToFileList:(NSString *)path error:(NSError **)error;

/*! 
    @method fileList
    @abstract Returns the instance's internal list of files.
    @discussion See the discussion on loadInternalListfile for more details on file lists.
        
        This method may returns an empty array if the instance doesn't 
        know about any of the files in the archive (or if the archive is empty).
    @result An NSArray containing all the known files stored the instance's archive.
*/
- (NSArray *)fileList;

#pragma mark file info

/*! 
    @method fileInfoEnumerator
    @abstract Returns an enumerator of file information dictionaries.
    @discussion File information dictionaries will always contain the following keys:
        
        * MPQFileSize: The size of the file in bytes as an integer.
        
        * MPQFileCompressedLength: The compressed size of the file in bytes as an integer.
        
        * MPQFileFlags: The file's flags as an integer. See the MPQFileFlag enum in 
        MPQSharedConstants.h for a list of valid bit values.
        
        * MPQFileLocale: The file's locale code as an integer. See the MPQLocale enum in 
        MPQSharedConstants.h for a list of valid values.
        
        * MPQFileHashA: The file's A hash as an integer. Mostly useless.
        
        * MPQFileHashB: The file's B hash as an integer. Mostly useless as well.
        
        * MPQFileHashPosition: The file's hash table position. Can be used as a unique key for that 
        particular file (in fact, a file's path is not a unique key, so this is the only unique key 
        for MPQ files).
        
        File information dictionaries may also contain the following key:
        
        * MPQFilename: The file's path inside the MPQ archive. Note that the path separator is \.
    @result An NSEnumerator subclass object you can use to cycle through the file information dictionaries. nil on failure.
*/
- (NSEnumerator *)fileInfoEnumerator;

/*!
    @method fileInfoForPosition:
    @abstract Returns the information dictionary for the file at the specified position
    @discussion File information dictionaries will always contain the following keys:
        
        * MPQFileSize: The size of the file in bytes as an integer.
        
        * MPQFileCompressedLength: The compressed size of the file in bytes as an integer.
        
        * MPQFileFlags: The file's flags as an integer. See the MPQFileFlag enum in 
        MPQSharedConstants.h for a list of valid bit values.
        
        * MPQFileLocale: The file's locale code as an integer. See the MPQLocale enum in 
        MPQSharedConstants.h for a list of valid values.
        
        * MPQFileHashA: The file's A hash as an integer. Mostly useless.
        
        * MPQFileHashB: The file's B hash as an integer. Mostly useless as well.
        
        * MPQFileHashPosition: The file's hash table position. Can be used as a unique key for that 
        particular file (in fact, a file's path is not a unique key, so this is the only unique key 
        for MPQ files).
        
        File information dictionaries may also contain the following key:
        
        * MPQFilename: The file's path inside the MPQ archive. Note that the path separator is \.
        
        Additionally, file information dictionaries may contain one or more MPQ file attribute keys.
        Please refer to the documentation of the header MPQSharedConstants.h for a list of valid keys.
    @param hash_position  An integer specifying the position of the file you wish information about. Must not be out of bounds.
    @result An NSDictionary object containing the file's information. nil on failure.
*/
- (NSDictionary *)fileInfoForPosition:(uint32_t)hash_position;
- (NSDictionary *)fileInfoForPosition:(uint32_t)hash_position error:(NSError **)error;

/*! 
    @method fileInfoForFile:locale:
    @abstract Returns the information dictionary for the specified file.
    @discussion File information dictionaries will always contain the following keys:
        
        * MPQFileSize: The size of the file in bytes as an integer.
        
        * MPQFileCompressedLength: The compressed size of the file in bytes as an integer.
        
        * MPQFileFlags: The file's flags as an integer. See the MPQFileFlag enum in 
        MPQSharedConstants.h for a list of valid bit values.
        
        * MPQFileLocale: The file's locale code as an integer. See the MPQLocale enum in 
        MPQSharedConstants.h for a list of valid values.
        
        * MPQFileHashA: The file's A hash as an integer. Mostly useless.
        
        * MPQFileHashB: The file's B hash as an integer. Mostly useless as well.
        
        * MPQFileHashPosition: The file's hash table position. Can be used as a unique key for that 
        particular file (in fact, a file's path is not a unique key, so this is the only unique key 
        for MPQ files).
        
        File information dictionaries may also contain the following key:
        
        * MPQFilename: The file's path inside the MPQ archive. Note that the path separator is \.
    @param filename The MPQ file path of the file you wish information about. Must not be nil.
    @param locale The file's locale code. See the MPQLocale enum in MPQSharedConstants.h for a list of valid values.
    @result An NSDictionary object containing the file's information. nil on failure or if the file is not found.
*/
- (NSDictionary *)fileInfoForFile:(NSString *)filename locale:(MPQLocale)locale;
- (NSDictionary *)fileInfoForFile:(NSString *)filename locale:(MPQLocale)locale error:(NSError **)error;

/*! 
    @method fileInfoForFiles:locale:
    @abstract Returns the information dictionary for the specified files.
    @discussion File information dictionaries will always contain the following keys:
        
        * MPQFileSize: The size of the file in bytes as an integer.
        
        * MPQFileCompressedLength: The compressed size of the file in bytes as an integer.
        
        * MPQFileFlags: The file's flags as an integer. See the MPQFileFlag enum in 
        MPQSharedConstants.h for a list of valid bit values.
        
        * MPQFileLocale: The file's locale code as an integer. See the MPQLocale enum in 
        MPQSharedConstants.h for a list of valid values.
        
        * MPQFileHashA: The file's A hash as an integer. Mostly useless.
        
        * MPQFileHashB: The file's B hash as an integer. Mostly useless as well.
        
        * MPQFileHashPosition: The file's hash table position. Can be used as a unique key for that 
        particular file (in fact, a file's path is not a unique key, so this is the only unique key 
        for MPQ files).
        
        File information dictionaries may also contain the following key:
        
        * MPQFilename: The file's path inside the MPQ archive. Note that the path separator is \.
        
        This method simply call fileInfoForFile:locale: for each entry in fileArray and places the result in order
        inside an NSArray.
    @param fileArray An array of MPQ file paths you wish information about. Must not be nil.
    @param locale The locale to be used for every file in fileArray.
    @result An NSArray of NSDictionary objects containing the files' information. nil on failure.
*/
- (NSArray *)fileInfoForFiles:(NSArray *)fileArray locale:(MPQLocale)locale;

#pragma mark adding

/*! 
    @method addFileWithPath:filename:parameters:
    @abstract Adds the specified file to the MPQ archive.
    @discussion This method adds the file at path to the MPQ archive as filename. Note that 
        the archive itself is not modified until writeToSave:atomically: is invoked.
        This method simply calls addFileWithData:filename:attributes:error:.
        
        The parameters dictionary is used to override the default parameters. It may be nil, or 
        have the following keys:
        
        * MPQFileFlags: The file's flags. Default flags are MPQFileCompressed. 
        Note that MPQFileValid is automatically added to the flags, so you do not need 
        to specify it here. In order to compress the file, OR the value MPQFileCompressed or 
        MPQFileDiabloCompressed (not recommended) to the file flags. See the MPQFileFlag enum in 
        the MPQSharedConstants.h header for other flag values.
        
        * MPQCompressor: The compressor that is going to be used for that particular file. 
        If this flag is not specified, the default compressor is used. Refer to the MPQCompressorFlag 
        documentation for details.
        
        * MPQCompressionQuality: If one of the compression flag is set, this is the compression quality that 
        will be used. Refer to the MPQCompressorFlag documentation for details.
        
        * MPQFileLocale: The file's locale. Default value is MPQNeutral. See the MPQLocale enum in 
        MPQSharedConstants.h for a list of valid values.
        
        * MPQOverwrite: Indicates if an existing file should be deleted. Default value is NO.
    @param path The absolute path of the file on disk. Must not be nil.
    @param filename The path of the file in the archive. Note that directorty separator is \. Must not be nil.
    @param parameters A NSDictionary containing file addition parameters. Pass nil for default parameters.
    @result YES on success or NO on failure.
*/
- (BOOL)addFileWithPath:(NSString *)path filename:(NSString *)filename parameters:(NSDictionary *)parameters;
- (BOOL)addFileWithPath:(NSString *)path filename:(NSString *)filename parameters:(NSDictionary *)parameters error:(NSError **)error;

/*! 
    @method addFileWithData:filename:parameters:
    @abstract Adds the specified data to the MPQ archive.
    @discussion This method adds the given data to the MPQ archive as filename. Note that 
        the archive itself is not modified until writeToSave:atomically: is invoked. As such, the 
        data will be retained until the archive has been saved.
        
        The parameters dictionary is used to override the default parameters. It may be nil, or 
        have the following keys:
        
        * MPQAddFlags: The file's flags. Default flags are MPQFileCompressed. 
        Note that MPQFileValid is automatically added to the flags, so you do not need 
        to specify it here. In order to compress the file, OR the value MPQFileCompressed or 
        MPQFileDiabloCompressed (not recommended) to the file flags. See the MPQFileFlag enum in 
        the MPQSharedConstants.h header for other flag values. If both MPQFileCompressed and 
        MPQFileDiabloCompressed are set, MPQFileCompressed takes precedence and MPQFileDiabloCompressed is cleared.
        
        * MPQAddCompressor: The compressor that is going to be used for that particular file. 
        If this flag is not specified, the default compressor is used. Refer to the MPQCompressorFlag 
        documentation for details.
        
        * MPQAddQuality: If either compression flag is set, this is the compression quality that 
        will be used. Refer to the MPQCompressorFlag documentation for details.
        
        * MPQAddLocale: The file's locale. Default value is MPQNeutral. See the MPQLocale enum in 
        MPQSharedConstants.h for a list of valid values.
        
        * MPQOverwrite: Indicates if an existing file should be deleted. Default value is NO.
    @param data The data to be added to the archive. Must not be nil.
    @param filename The path of the file in the archive. Note that directorty separator is \. Must not be nil.
    @param parameters A NSDictionary containing file addition parameters. Can be nil.
    @result YES on success or NO on failure.
*/
- (BOOL)addFileWithData:(NSData *)data filename:(NSString *)filename parameters:(NSDictionary *)parameters;
- (BOOL)addFileWithData:(NSData *)data filename:(NSString *)filename parameters:(NSDictionary *)parameters error:(NSError **)error;

- (BOOL)addFileWithDataSourceProxy:(MPQDataSourceProxy *)dataSourceProxy filename:(NSString *)filename parameters:(NSDictionary *)parameters error:(NSError **)error;

#pragma mark delete

/*! 
    @method deleteFile:
    @abstract Deletes the specified file from the MPQ archive.
    @discussion Note that when deleting files from MPQ archives, the file is simply marked
        as deleted. The data itself isn't removed from the archive file. That is to say, deleting 
        a file will not decrease the size of the archive.
        
        Note that this method simply calls deleteFile:locale: with MPQNeutral as the locale.
    @param filename The path of the MPQ file to delete. Note that the path separator MUST be \. Must not be nil.
    @result YES on success or NO on failure.
*/
- (BOOL)deleteFile:(NSString *)filename;
- (BOOL)deleteFile:(NSString *)filename error:(NSError **)error;

/*! 
    @method deleteFile:locale:
    @abstract Deletes the specified file with the specified locale from the MPQ archive.
    @discussion Note that when deleting files from MPQ archives, the file is simply marked
        as deleted. The data itself isn't removed from the archive file. That is to say, deleting 
        a file will not decrease the size of the archive.
    @param filename The path of the MPQ file to delete. Note that the path separator MUST be \. Must not be nil.
    @param locale The file's locale code. See the MPQLocale enum in MPQSharedConstants.h for a list of valid values.
    @result YES on success or NO on failure.
*/
- (BOOL)deleteFile:(NSString *)filename locale:(MPQLocale)locale;
- (BOOL)deleteFile:(NSString *)filename locale:(MPQLocale)locale error:(NSError **)error;

/*
    @method renameFile:as:
    @abstract Renames the specified file as the new specified file.
    @discussion Renaming isn't as simple as it sounds. Indeed, since a file's hash table position 
        and file key are based on its file name (MPQ file path), renaming involves reading the 
        file's data, deleting the old file and adding a new one with the file's data under the new name.
        
        Note that this method simply calls renameFile:as:locale: with MPQNeutral as the locale.
    @param old_filename The path of the MPQ file to rename. Note that the path separator MUST be \. Must not be nil.
    @param new_filename The new path of the MPQ file. Note that the path separator MUST be \. Must not be nil.
    @result YES on success or NO on failure.
*/
// TODO: - (BOOL)renameFile:(NSString *)old_filename as:(NSString *)new_filename;

/*
    @method renameFile:as:locale:
    @abstract Renames the specified file with the specified locale as the new specified file.
    @discussion Renaming isn't as simple as it sounds. Indeed, since a file's hash table position 
        and file key are based on its file name (MPQ file path), renaming involves reading the 
        file's data, deleting the old file and adding a new one with the file's data under the new name.
    @param old_filename The path of the MPQ file to rename. Note that the path separator MUST be \. Must not be nil.
    @param new_filename  The new path of the MPQ file. Note that the path separator MUST be \. Must not be nil.
    @param locale The old and new file's locale code. See the MPQLocale enum in MPQSharedConstants.h for a list of valid values.
    @result YES on success or NO on failure.
*/
// TODO: - (BOOL)renameFile:(NSString *)old_filename as:(NSString *)new_filename locale:(MPQLocale)locale;

#pragma mark opening

/*! 
    @method openFile:
    @abstract Creates an MPQFile object for the specified file.
    @discussion MPQFile objects are useful for streaming a file's data. For one-time data reading, 
        you may use the dataForFile methods.
        
        Note that this method simply calls openFile:locale: with MPQNeutral as the locale.
    @param filename The filename of the MPQ file to open. Note that the path separator MUST be \. Must not be nil.
    @result An MPQFile instance on success or nil on failure.
*/
- (MPQFile *)openFile:(NSString *)filename;
- (MPQFile *)openFile:(NSString *)filename error:(NSError **)error;

/*! 
    @method openFile:locale:
    @abstract Creates an MPQFile object for the specified file.
    @discussion MPQFile objects are useful for streaming a file's data. For one-time data reading, 
        you may use the dataForFile methods.
    @param filename The filename of the MPQ file to open. Note that the path separator MUST be \. Must not be nil.
    @param locale The old and new file's locale code. See the MPQLocale enum in MPQSharedConstants.h for a list of valid values.
    @result An MPQFile instance on success or nil on failure.
*/
- (MPQFile *)openFile:(NSString *)filename locale:(MPQLocale)locale;
- (MPQFile *)openFile:(NSString *)filename locale:(MPQLocale)locale error:(NSError **)error;

- (MPQFile *)openFileAtPosition:(uint32_t)hash_position error:(NSError **)error;

#pragma mark reading

/*! 
    @method copyDataForFile:
    @abstract Returns the entire content of the specified file.
    @discussion Note that this method simply calls copyDataForFile:range:locale: with {0,0} as the range 
        and MPQNeutral as the locale.
        
        If you intend on streaming a file, you should not use the copyDataForFile methods, but rather 
        use the openFile methods to get a MPQFile object for the desired file.
    @param filename The path of the MPQ file to read from. Note that the path separator MUST be \. Must not be nil.
    @result An NSData instance containing the requested data on success or nil on failure.
*/
- (NSData *)copyDataForFile:(NSString *)filename;
- (NSData *)copyDataForFile:(NSString *)filename error:(NSError **)error;

/*! 
    @method copyDataForFile:range:
    @abstract Returns the specified range of bytes from the specified file.
    @discussion Note that this method simply calls copyDataForFile:range:locale: with MPQNeutral as the locale.
        
        If you intend on streaming a file, you should not use the dataForFile methods, but rather 
        use the openFile methods to get a MPQFile object for the desired file.
    @param filename The path of the MPQ file to read from. Note that the path separator MUST be \. Must not be nil.
    @param dataRange An NSRange struct specifying the range of bytes to read. Note that specifying 0 
        as the length will return all the data from the starting offset up until the end of file.
    @result An NSData instance containing the requested data on success or nil on failure.
*/
- (NSData *)copyDataForFile:(NSString *)filename range:(NSRange)dataRange;
- (NSData *)copyDataForFile:(NSString *)filename range:(NSRange)dataRange error:(NSError **)error;

/*! 
    @method copyDataForFile:locale:
    @abstract Returns the entire content of the specified file with the specified locale.
    @discussion Note that this method simply calls copyDataForFile:range:locale: with {0,0} as the range.
        
        If you intend on streaming a file, you should not use the dataForFile methods, but rather 
        use the openFile methods to get a MPQFile object for the desired file.
    @param filename The path of the MPQ file to read from. Note that the path separator MUST be \. Must not be nil.
    @param locale The file's locale code. See the MPQLocale enum in MPQSharedConstants.h for a list of valid values.
    @result An NSData instance containing the requested data on success or nil on failure.
*/
- (NSData *)copyDataForFile:(NSString *)filename locale:(MPQLocale)locale;
- (NSData *)copyDataForFile:(NSString *)filename locale:(MPQLocale)locale error:(NSError **)error;

/*! 
    @method copyDataForFile:range:locale:
    @abstract Returns the specified range of bytes from the specified file with the specified locale.
    @discussion If you intend on streaming a file, you should not use the dataForFile methods, but rather 
        use the openFile methods to get a MPQFile object for the desired file.
    @param filename The path of the MPQ file to read from. Note that the path separator MUST be \. 
        Must not be nil.
    @param dataRange An NSRange struct specifying the range of bytes to read. Note that specifying 0 
        as the length will return all the data from the starting offset up until the end of file.
    @param locale The file's locale code. See the MPQLocale enum in 
        MPQSharedConstants.h for a list of valid values.
    @result An NSData instance containing the requested data on success or nil on failure.
*/
- (NSData *)copyDataForFile:(NSString *)filename range:(NSRange)dataRange locale:(MPQLocale)locale;
- (NSData *)copyDataForFile:(NSString *)filename range:(NSRange)dataRange locale:(MPQLocale)locale error:(NSError **)error;

#pragma mark existence

/*! 
    @method fileExists:
    @abstract Checks if a specified file exists in the MPQ archive.
    @discussion This method simply calls fileExists:locale: with MPQNeutral as the locale.
    @param filename The path of the MPQ file to search for. Note that the path separator MUST be \. Must not be nil.
    @result YES if the file exists, or NO if it does not.
*/
- (BOOL)fileExists:(NSString *)filename;
- (BOOL)fileExists:(NSString *)filename error:(NSError **)error;

/*! 
    @method fileExists:locale:
    @abstract Checks if a specified file exists in the MPQ archive for a specified locale.
    @discussion A file's path and locale are the two values necessary to uniquely identify a file in an MPQ archive.
    @param filename The path of the MPQ file to search for. Note that the path separator MUST be \. Must not be nil.
    @param locale The file's locale code. See the MPQLocale enum in MPQSharedConstants.h for a list of valid values.
    @result YES if the file exists, or NO if it does not.
*/
- (BOOL)fileExists:(NSString *)filename locale:(MPQLocale)locale;
- (BOOL)fileExists:(NSString *)filename locale:(MPQLocale)locale error:(NSError **)error;

/*! 
    @method localesForFile:
    @abstract Returns an array of locale codes for which the specified file exists.
    @discussion Files can have the same path in an MPQ archive so long as their locale is different.
    @param filename The path of the MPQ file to search for. Note that the path separator MUST be \. Must not be nil.
    @result An autoreleased NSArray instance containing the the list of locale codes for which the file exists, 
        or nil if the file does not exists.
*/
- (NSArray *)localesForFile:(NSString *)filename;

#pragma mark writing

/*! 
    @method writeToFile:atomically:
    @abstract Writes the archive at path.
    @discussion If path is the same as the path that was used to initialize the instance, 
		the archive file is modified directly. If path is different than the path used to initialize 
		the instance, a new file is created at path and a new archive is written there (save-as operation). 
		Furthermore, the archive path of the instance is changed to the new path and the old archive is closed.
        
        If the archive was not initialized with a path, a new file is created at path and the path of the 
        instance is set to path.
        
        In all cases, setting atomically to YES makes the instance close the archive file (if there is one) and 
		create a new temporary archive file which will be moved to path once it has been fully written to disk. 
		Note that the temporary file is actually a copy of the original archive file, so if the archive is embedded 
		in some other file, all data not belonging to the archive is preserved.
        
        In all cases, if the method returns NO and atomically was YES or path was different from the instance's 
        initial path, the instance will be exactly as it was prior to the invocation. Otherwise, there are no garantees 
        on the state of the archive on disk or of the instance.
    @param path The location where to save the archive. Must not be nil.
    @param atomically If atomically is YES, modifications are performed on a copy of the archive which is moved 
        to the final destination only at the end. Requires as much free space as the size of the archive, plus any 
        additional space required for new files or other operations on the archive that may increase its size.
    @result Returns YES if writing was sucessful or NO if an error occured. On error, if flag was YES, the instance 
        is re-initialized with the original archive on disk (if there was an original). The instance is 
        marked as not modified if this method succeeds.
*/
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically;
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomically error:(NSError **)error;

@end

/*!
    @category NSObject (MPQArchiveDelegate)
    @discussion The MPQArchiveDelegate delegate is used to report on the activity and status of 
        an MPQ archive and provide access management features to clients pertaining to all the 
        framework operations, such as adding, deleting, opening, etc.
*/
@interface NSObject (MPQArchiveDelegate)

/*!
    @method archiveShouldSave:
    @abstract This method is called immediately before saving an archive.
    @discussion Return YES in this delegate to perform the save operation, or NO to cancel the save operation.
    @param archive The archive that is about to be saved.
    @result A response from the delegate.
*/
- (BOOL)archiveShouldSave:(MPQArchive *)archive;

/*!
    @method archiveWillSave:
    @abstract This method is called immediately before saving an archive but after
        archiveShouldSave: if it is implemented by the delegate.
    @discussion This message is always sent if the delegate implements it.
    @param archive The archive that is about to be saved.
*/
- (void)archiveWillSave:(MPQArchive *)archive;

/*!
    @method archiveDidSave:
    @abstract This method is called immediately after saving an archive.
    @discussion archiveDidSave: will not be sent to the delegate if the save operation failed.
    @param archive The archive that did save.
*/
- (void)archiveDidSave:(MPQArchive *)archive;

/*!
    @method archive:shouldAddFile:
    @abstract This method is called immediately before adding a file to an archive.
    @discussion This method is invoked when adding a file to the archive but prior to that file
        being actually compressed and written in the MPQ archive file. Return YES to permit the
        addition or NO to cancel it. Note that the new file will be accessible right after the
        addition method returns (if it was sucessfull). However, the data of the file will be 
        read from the original file on disk until the archive is saved, at which time the 
        delegate will be notified that the file is being compressed (if compression was 
        specified) and added to the MPQ archive file.
    @param archive The archive in which the file will be added.
    @param filename The MPQ filename of the file that is about to be added.
    @result A response from the delegate.
*/
- (BOOL)archive:(MPQArchive *)archive shouldAddFile:(NSString *)filename;

/*!
    @method archive:willAddFile:
    @abstract This method is called immediately before the framework starts compressing a file into an archive.
    @discussion This method is called for each file pending for addition in the archive being 
        saved. This method is invoked after archiveWillSave: but prior to archiveDidSave:.
    @param archive The archive in which the file will be added.
    @param filename The MPQ filename of the file that is about to be added.
*/
- (void)archive:(MPQArchive *)archive willAddFile:(NSString *)filename;

/*!
    @method archive:didAddFile:
    @abstract This method is called immediately after the framework compressed a file into an archive.
    @discussion This message is sent regardless if the file was compressed or not, encrypted or not.
    @param archive The archive in which the file was added.
    @param filename The MPQ filename of the file that was added.
*/
- (void)archive:(MPQArchive *)archive didAddFile:(NSString *)filename;

/*!
    @method archive:shouldDeleteFile:
    @abstract This method is called immediately before deleting a file from an archive.
    @discussion Return YES to permit the addition or NO to cancel it.
    @param archive The archive in which file will be deleted.
    @param filename The MPQ filename of the file that is about to be deleted.
    @result A response from the delegate.
*/
- (BOOL)archive:(MPQArchive *)archive shouldDeleteFile:(NSString *)filename;

/*!
    @method archive:willDeleteFile:
    @abstract This method is called immediately before the framework deletes a file from an archive.
    @discussion This method is invoked after archive:shouldDeleteFile:. Note that unlike file
        addition and renaming, archive:willDeleteFile: and archive:didDeleteFile: are not
        invoked when the archive is saved, but rather immediately before and after the delete file 
        method is invoked respectively. This is because no extra operation 
        is performed at save time for deletion, unlike addition and renaming. Note however that 
        deletion is undoable until the archive is saved.
    @param archive The archive from which file will be deleted.
    @param filename The MPQ filename of the file that is about to be deleted.
*/
- (void)archive:(MPQArchive *)archive willDeleteFile:(NSString *)filename;

/*!
    @method archive:didDeleteFile:
    @abstract This method is called immediately after the framework deleted a file from an archive.
    @discussion Note that unlike file 
        addition and renaming, archive:willDeleteFile: and archive:didDeleteFile: are not 
        invoked when the archive is saved, but rather immediately before and after the delete file 
        method is invoked respectively. This is because no extra operation 
        is performed at save time for deletion, unlike addition and renaming. Note however that 
        deletion is undoable until the archive is saved.
    @param archive The archive from which file was deleted.
    @param filename The MPQ filename of the file that was deleted.
*/
- (void)archive:(MPQArchive *)archive didDeleteFile:(NSString *)filename;

/*!
    @method archive:shouldRenameFile:as:
    @abstract This method is called immediately before renaming a file of an archive.
    @discussion This method is invoked when renaming a file of the archive but prior to that file
        being actually re-encrypted and re-written in the MPQ archive file. Return YES to permit the
        rename or NO to cancel it. Note that the file will be accessible right after the
        rename method returns (if it was sucessfull) as the new name. The 
        delegate will be notified that the file is being re-processed at save time.
    @param archive The archive in which the file to be renamed is stored.
    @param filename The MPQ filename of the file that is about to be renamed.
    @param newFilename The new MPQ filename of the file that is about to be renamed.
    @result A response from the delegate.
*/
- (BOOL)archive:(MPQArchive *)archive shouldRenameFile:(NSString *)filename as:(NSString *)newFilename;

/*!
    @method archive:willRenameFile:as:
    @abstract This method is called immediately before the framework starts renaming a file
        of an archive.
    @discussion This method is called for each file pending for renaming in the archive being 
        saved. This method is invoked after archiveWillSave: but prior to archiveDidSave:.
    @param archive The archive in which the file to be renamed is stored.
    @param filename The MPQ filename of the file that is about to be renamed.
    @param newFilename The new MPQ filename of the file that is about to be renamed.
*/
- (void)archive:(MPQArchive *)archive willRenameFile:(NSString *)filename as:(NSString *)newFilename;

/*!
    @method archive:didRenameFile:as:
    @abstract This method is called immediately after the framework renamed a file
        of an archive.
    @discussion It is safe to use the new name as soon as this message is sent.
    @param archive The archive in which the renamed file is stored.
    @param filename The MPQ filename of the file that was renamed.
    @param newFilename The new MPQ filename of the file that was renamed.
*/
- (void)archive:(MPQArchive *)archive didRenameFile:(NSString *)filename as:(NSString *)newFilename;

/*!
    @method archive:shouldOpenFile:
    @abstract This method is called immediately before opening a file of the archive.
    @discussion Return YES to permit the file to be opened or NO to prevent it.
    @param archive The archive containing the file that is about to be opened.
    @param filename The MPQ filename of the file that is about to be opened.
    @result A response from the delegate.
*/
- (BOOL)archive:(MPQArchive *)archive shouldOpenFile:(NSString *)filename;

/*!
    @method archive:willOpenFile:
    @abstract This method is called immediately before opening a file of the archive.
    @discussion This method is invoked after archive:shouldOpenFile:.
    @param archive The archive containing the file that is about to be opened.
    @param filename The MPQ filename of the file that is about to be opened.
*/
- (void)archive:(MPQArchive *)archive willOpenFile:(NSString *)filename;

/*!
    @method archive:didOpenFile:
    @abstract This method is called immediately after the framework opened a file
        from an archive.
    @discussion This method is invoked after archive:willOpenFile:.
    @param archive The archive from which file was opened.
    @param file The MPQFile instance for the file that was opened.
*/
- (void)archive:(MPQArchive *)archive didOpenFile:(MPQFile *)file;

@end
