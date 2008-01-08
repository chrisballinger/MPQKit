# Makefile for compiling MPQKit
#
# Author : Xavier Glattard <xavier.glattard@online.fr>
# Created: Tue Oct 02 2007

include $(GNUSTEP_MAKEFILES)/common.make

SUBPROJECT_NAME = stormlib2

stormlib2_C_FILES = \
	SCompression.cpp \

stormlib2_SUBPROJECTS = \
	huffman \
	pklib \
	wave \

-include Makefile.preamble
include $(GNUSTEP_MAKEFILES)/subproject.make
-include Makefile.postamble
