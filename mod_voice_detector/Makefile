# Makefile for FreeSWITCH Voice Detector Module

# FreeSWITCH source directory (adjust this path as needed)
FREESWITCH_DIR ?= /usr/local/src/freeswitch-1.10.12.-release

# Module name
MODULE_NAME = mod_voice_detector

# Source files
SOURCES = mod_voice_detector.c

# Object files
OBJECTS = $(SOURCES:.c=.o)

# Compiler and flags
CC = gcc
CFLAGS = -fPIC -Wall -Wextra -O2 -g
INCLUDES = -I$(FREESWITCH_DIR)/src/include -I$(FREESWITCH_DIR)/src/include/switch

# Libraries
LIBS = -lcurl -ljson-c

# Default target
all: $(MODULE_NAME).so

# Build the shared library
$(MODULE_NAME).so: $(OBJECTS)
	$(CC) -shared -o $@ $(OBJECTS) $(LIBS)

# Compile source files
%.o: %.c
	$(CC) $(CFLAGS) $(INCLUDES) -c $< -o $@

# Clean build files
clean:
	rm -f $(OBJECTS) $(MODULE_NAME).so

# Install module
install: $(MODULE_NAME).so
	cp $(MODULE_NAME).so $(FREESWITCH_DIR)/src/mod/
	cp ../../config/voice_detector.conf $(FREESWITCH_DIR)/conf/

# Uninstall module
uninstall:
	rm -f $(FREESWITCH_DIR)/src/mod/$(MODULE_NAME).so
	rm -f $(FREESWITCH_DIR)/conf/voice_detector.conf

# Dependencies
$(OBJECTS): mod_voice_detector.h

.PHONY: all clean install uninstall
