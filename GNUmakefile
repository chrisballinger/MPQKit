# Makefile for compiling MPQKit
#
# Author : Xavier Glattard <xavier.glattard@online.fr>
# Created: Tue Oct 02 2007

include $(GNUSTEP_MAKEFILES)/common.make

FRAMEWORK_NAME = MPQKit
TOOL_NAME = mpqdump mpqdumpsectors
CTOOL_NAME = dumpkeys

MPQKit_INCLUDE_DIRS = -I ./stormlib2 -I ..

MPQKit_HEADER_FILES = \
	MPQArchive.h \
	MPQArchivePriorityProxy.h \
	MPQArchivePrivate.h \
	MPQByteOrder.h \
	MPQCryptography.h \
	MPQDataSource.h \
	MPQErrors.h \
	MPQFile.h \
	MPQFileInfoEnumerator.h \
	MPQFilePrivate.h \
	MPQKit.h \
	MPQKitPrivate.h \
	MPQSharedConstants.h \
	NSArrayListfileAdditions.h \
	NSDataCryptoAdditions.h \
	NSDateNTFSAdditions.h \
	NSStringAdditions.h \
	PHSErrorMacros.h \
	stormlib2/SCompression.h \
	stormlib2/huffman/huff.h \
	stormlib2/pklib/pklib.h \
	stormlib2/wave/wave.h

MPQKit_OBJC_FILES = \
	MPQArchive.m \
	MPQArchivePriorityProxy.m \
	MPQDataSource.m \
	MPQErrors.m \
	MPQFileInfoEnumerator.m \
	MPQFile.m \
	NSArrayListfileAdditions.m \
	NSDataCryptoAdditions.m \
	NSDateNTFSAdditions.m \
	NSStringAdditions.m \

MPQKit_C_FILES = \
	MPQCryptography.c \
	stormlib2/pklib/crc32.c \
	stormlib2/pklib/explode.c \
	stormlib2/pklib/implode.c \
	stormlib2/wave/wave.c \
	stormlib2/SCompression.cpp \
	stormlib2/huffman/huff.cpp \

mpqdump_OBJC_FILES = \
	mpqdump.m \

mpqdump_LIB_DIRS = -L MPQKit.framework -L stormlib2
mpqdump_TOOL_LIBS = -lMPQKit -lStorm2 -lstdc++ -lz -lbz2 -lcrypto

mpqdumpsectors_OBJC_FILES = \
	mpqdumpsectors.m \

mpqdumpsectors_LIB_DIRS = -L MPQKit.framework -L stormlib2
mpqdumpsectors_TOOL_LIBS = -lMPQKit -lStorm2 -lstdc++ -lz -lbz2 -lcrypto

dumpkeys_C_FILES = \
	dumpkeys.c \

dumpkeys_LDFLAGS = -lssl

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/framework.make
include $(GNUSTEP_MAKEFILES)/tool.make
include $(GNUSTEP_MAKEFILES)/ctool.make
-include GNUmakefile.postamble
