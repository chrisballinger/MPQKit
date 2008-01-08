# Makefile for compiling MPQKit
#
# Author : Xavier Glattard <xavier.glattard@online.fr>
# Created: Tue Oct 02 2007

include $(GNUSTEP_MAKEFILES)/common.make

SUBPROJECT_NAME = pklib

pklib_INCLUDE_DIRS = -I. -I.. -I../..

pklib_C_FILES = \
	crc32.c \
	explode.c \
	implode.c \

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/subproject.make
-include GNUmakefile.postamble
