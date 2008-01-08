# Makefile for compiling MPQKit
#
# Author : Xavier Glattard <xavier.glattard@online.fr>
# Created: Tue Oct 02 2007

include $(GNUSTEP_MAKEFILES)/common.make

SUBPROJECT_NAME = stormlib2

stormlib2_INCLUDE_DIRS = -I. -I..

stormlib2_CC_FILES = \
	SCompression.cpp \

stormlib2_SUBPROJECTS = \
	huffman \
	pklib \
	wave \

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/subproject.make
-include GNUmakefile.postamble
