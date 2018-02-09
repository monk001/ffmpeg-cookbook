# Copyright 2018 lzy0168@gmail.com

ifeq ($(platforms),android)
  OS=$(shell uname)
  HOST_ARCH=$(shell uname -m)
  HOST_SYSTEM=linux-$(HOST_ARCH)

  NDK_BUILD_PATH=$(shell which ndk-build)
  ANDROID_NDK_HOME=$(shell dirname $(NDK_BUILD_PATH))

  SYSROOT=$(shell find $(ANDROID_NDK_HOME)/platforms -maxdepth 1 -name android-19 | sort -r | head -1)/arch-arm
  #SYSROOT=$(shell find $(ANDROID_NDK_HOME)/platforms -maxdepth 1 -name android-1[4-9] -o -name android-2* | sort | head -1)/arch-arm
  CROSS_PREFIX=$(shell find $(ANDROID_NDK_HOME)/toolchains/ -maxdepth 1 -name arm-linux-androideabi-[1-9]* | sort -r | head -1)/prebuilt/$(HOST_SYSTEM)/bin/arm-linux-androideabi-

  CC=$(CROSS_PREFIX)gcc --sysroot=$(SYSROOT)
  CXX=$(CROSS_PREFIX)g++ --sysroot=$(SYSROOT)
  LD=$(CROSS_PREFIX)ld --sysroot=$(SYSROOT)
  RANLIB=$(CROSS_PREFIX)ranlib
  AR=$(CROSS_PREFIX)ar
  STRIP=$(CROSS_PREFIX)strip
  NM=$(CROSS_PREFIX)nm
else
  platforms=linux

  STRIP=strip
endif

FF_VER:=$(shell find out/$(platforms)/ffmpeg -maxdepth 1 -type d -name "[0-9]*" | sort -r | head -1)
FF_VER:=$(shell basename $(FF_VER))

FF_ROOT=out/$(platforms)/ffmpeg/${FF_VER}
FF_INC_HOME=$(FF_ROOT)/include
FF_LIB_HOME=$(FF_ROOT)/lib
FF_BIN_HOME=$(FF_ROOT)/bin

CFLAGS += -fvisibility=default -D__DragonFly__ -Wall -Wextra -Wno-deprecated-declarations -Wno-missing-field-initializers
LDFLAGS += -fno-exceptions

ifeq ($(debug),1)
CFLAGS += -g -DDEBUG
LDFLAGS += -ggdb
else
CFLAGS += -DNDEBUG
LDFLAGS += -O2 -Os
endif

ifeq ($(platforms),android)
CFLAGS += -pie -fPIE -D__ANDROID__=1 -DANDROID
LDFLAGS += -pie -fPIE
else
CFLAGS += -fPIC
LDFLAGS += -fpic -fPIC -Wl,-Bsymbolic
endif

SYS_LIBS += -ldl -lm -lz

ifeq ($(platforms),android)
SYS_LIBS += -llog
endif

ifeq ($(use_ffmpeg),1)
CFLAGS += -DUC_CODEC_USE_FFMPEG -I$(FF_INC_HOME)
FF_LIBS = -L$(FF_LIB_HOME) -lswscale -lswresample -lavcodec -lavformat -lavutil -lavfilter
else
 ifeq ($(use_ffmpeg_header), 1)
  CFLAGS += -DUC_CODEC_USE_FFMPEG_HEADER -I$(FF_INC_HOME)
 endif
FF_LIBS =
endif

SRCS=samples/uc_codec.c samples/audio_decoder_test.c

audio_decoder_test: $(SRCS) Makefile
	@$(CC) -o $@ $(SRCS) $(LDFLAGS) $(CFLAGS)
	@echo " audio_decoder_test created [for $(platforms)]"

clean:
	@rm -rfv audio_decoder_test

ifeq ($(platforms),android)
MKFFMPEG="$(CC) -o $(FF_BIN_HOME)/libffmpeg_nostrip.so $(LDFLAGS) -shared -Wl,--no-whole-archive $(SYS_LIBS) -Wl,--whole-archive $(FF_LIBS) -Wl,--no-whole-archive"
else
MKFFMPEG="$(CC) -o $(FF_BIN_HOME)/libffmpeg_nostrip.so $(LDFLAGS) -shared $(SYS_LIBS) $(FF_LIBS)"
endif

libffmpeg: $(FF_LIB_HOME)/libavformat.a $(FF_LIB_HOME)/libavcodec.a
	@echo "-------------------------------------------------------------"
	@echo "create $(FF_BIN_HOME)/libffmpeg.so"
	@mkdir -p $(FF_BIN_HOME)
	@eval "$(MKFFMPEG)"
	@$(STRIP) $(FF_BIN_HOME)/libffmpeg_nostrip.so -o $(FF_BIN_HOME)/libffmpeg.so

help:
	@echo "command line:"
	@echo "  make [platforms=android] [debug=1] [use_ffmpeg=1] [use_ffmpeg_header=1]"
