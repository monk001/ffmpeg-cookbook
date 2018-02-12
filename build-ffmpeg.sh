#!/bin/bash

shopt -s extglob
shopt -s nocasematch

in_root=$(pwd)

cd $(dirname $0)

usage() {
  echo "usage:"
  echo "  .build-ffmpeg.sh [linux|android|windows] [debug] ffmpeg.package/ffmpeg-2.4.13.tar.bz2"
  exit 1
}

platforms=
ffmpeg_archive=
debug=0

while [[ ! -z "$1" ]]
do
  case "$1" in
    linux)   platforms=linux;;
    android) platforms=android;;
    windows) platforms=windows;;
    debug)   debug=1;;
    *) if [[ -f "$(pwd)/$1" ]]; then ffmpeg_archive="$(pwd)/$1"; fi;;
  esac
  shift
done

if [[ -z "$platforms" ]]; then
  case "$(uname -s)" in
    linux*) platforms=linux;;
    mingw*) platforms=windows;;
    *) echo "unsupport system";;
  esac
fi

if [[ -z "$platforms" ]]; then
  usage
fi

if [[ -z "$ffmpeg_archive" ]]; then
  usage
  exit -1
fi

ENABLES=(
  static
)

DISABLE=(
  shared

  gpl
  nonfree
  version3
  symver
  encoders
  muxers

#  vdpau
#  x11grab

  ffplay ffprobe ffserver doc
)

if [[ "$platforms" != "android" ]]; then
 ENABLES=(${ENABLES[@]}
   pic
 )
fi

if [[ "$debug" == "0" ]]; then
 DISABLE=(${DISABLE[@]}
  debug
 )
fi

CFLAGS="${CFLAGS} -fvisibility=default -D__DragonFly__ -Wall -Wextra"
CFLAGS="${CFLAGS} -Wno-deprecated-declarations -Wno-missing-field-initializers"
CFLAGS="${CFLAGS} -Wno-sign-compare -Wno-unused-parameter -Wno-old-style-declaration"
CFLAGS="${CFLAGS} -Wno-deprecated-declarations -Wno-deprecated-declaration"

LDFLAGS="${LDFLAGS} -fno-exceptions"

if [[ "$debug" == "1" ]]; then
 CFLAGS="${CFLAGS} -g -DDEBUG"
 LDFLAGS="${LDFLAGS} -ggdb"
else
 CFLAGS="${CFLAGS} -DNDEBUG"
 LDFLAGS="${LDFLAGS} -O2 -Os"
fi

if [[ "$platforms" == "android" ]]; then
 CFLAGS="${CFLAGS} -D__ANDROID__=1 -DANDROID"
 CFLAGS="${CFLAGS} -pie -fPIE"
 LDFLAGS="${LDFLAGS} -pie -fPIE"
else
 CFLAGS="${CFLAGS} -fPIC"
 LDFLAGS="${LDFLAGS} -fpic -fPIC"
fi

ffmpeg_archive_name=$(basename $ffmpeg_archive)
ffmpeg_archive_name="${ffmpeg_archive_name%.tar.*}"

# determine OS and architecture
OS_ARCH=$(uname -sm | tr 'A-Z' 'a-z' | sed "s/\ /\-/g")

# android level
NDK_LEVEL=19
#ARCHES="armv5te armv7a mips x86_64"
ARCHES="armv7a"

COMPILER=gcc

function die {
  err="Unknown error!"
  test "$platforms" && err=$1
  cd ${in_root}
  echo "$err"
  exit -1
}

function build_ffmpeg_android {
  echo "Building ffmpeg for android ..."

  NDK_ROOT=`which ndk-build`
  NDK_ROOT=`dirname ${NDK_ROOT} 2>/dev/null`

  test -d "${NDK_ROOT}" || die "ndk not found!"

  #**************************
  # setting

  if [[ $ARCH == arm* ]]; then
    CPU=arm
  else
    die "Unsupport arch ${ARCH}"
  fi

  if [[ "$COMPILER" == "gcc" ]]; then
    GCC=$(find ${NDK_ROOT}/toolchains -name "*$CPU*gcc" | sort -r | head -1)
    test -f "${GCC}" || die "cross compiler gcc not found!"
    CROSS_PREFIX=${GCC::-3}
  else
    die "Unsupport compiler $COMPILER"
  fi

  SYSROOT=${NDK_ROOT}/platforms/android-${NDK_LEVEL}/arch-${CPU}

  CFLAGS="${CFLAGS} -mthumb -std=c99 -O3 -Wall -pipe -fasm -finline-limit=300 -ffast-math -fstrict-aliasing -Werror=strict-aliasing -Wno-psabi -Wa,--noexecstack -fdiagnostics-color=always -march=armv7-a -mfpu=neon -mfloat-abi=softfp -mvectorize-with-neon-quad"

  LDFLAGS="${LDFLAGS} -Wl,--no-undefined -Wl,-z,noexecstack"

  libs=

  if [[ "$CPU" == "arm" ]]; then
    CFLAGS="${CFLAGS} -marm"
  fi

  #----------------------
  # ARM Options
  #   https://gcc.gnu.org/onlinedocs/gcc/ARM-Options.html

  if [[ "${ARCH}" = "armv5te" ]]; then
    CFLAGS="${CFLAGS}"
    CFLAGS="${CFLAGS} -D__ARM_ARCH_5__ -D__ARM_ARCH_5T__ -D__ARM_ARCH_5E__ -D__ARM_ARCH_5TE__"
    CFLAGS="${CFLAGS} -march=armv5te -mtune=xscale"
  elif [[ "${ARCH}" = "armv7a" ]]; then
    CFLAGS="${CFLAGS}"
    CFLAGS="${CFLAGS} -march=armv7-a -mfloat-abi=softfp -mfpu=neon"
    LDFLAGS="${LDFLAGS} -Wl,--fix-cortex-a8"
  else
    die "Unsupport arch ${ARCH}"
  fi

  #------------------------------
  # configure disable and enable

  #------------------------------
  # others

  if [[ ! -f config.mak ]]; then
    echo "ffmpeg configure ..."

    ./configure \
      --cross-prefix=${CROSS_PREFIX} \
      --sysroot=${SYSROOT} \
      --prefix=${dist_root} \
      \
      --arch=${CPU} \
      --target-os=android \
      --enable-cross-compile \
      \
      --enable-small \
      --disable-symver \
      \
      ${FEATURES} \
      \
      --extra-cflags="${CFLAGS}" \
      --extra-cxxflags="${CFLAGS}" \
      \
      --extra-ldflags="${LDFLAGS}" \
      \
      --extra-libs="${libs}" \
      \
      --pkg-config=$(which pkg-config) \
      || die "Couldn't configure ffmpeg!"

    sed -i "s/#define HAVE_LOG2 1/#define HAVE_LOG2 0/" config.h
    sed -i "s/#define HAVE_LOG2F 1/#define HAVE_LOG2F 0/" config.h

    # build
    make clean   || die "Couldn't clean ffmpeg!"
    make -j$(($(nproc)-1)) || die "Couldn't build ffmpeg!"
  else
    make
  fi

  make install || die "Couldn't install ffmpeg!"
}

function build_ffmpeg_linux() {
  echo "Building ffmpeg for linux ..."

  #**************************
  # setting

  libs=

  if [[ ! -f config.mak ]]; then
    #------------------------------
    # configure disable and enable

    #------------------------------
    # others

    echo "ffmpeg configure ..."

    ./configure \
      --prefix=${dist_root} \
      \
      ${FEATURES} \
      \
      --extra-cflags="${CFLAGS}" \
      --extra-cxxflags="${CFLAGS}" \
      \
      --extra-ldflags="${LDFLAGS}" \
      \
      --extra-libs="${libs}" \
      \
      --pkg-config=$(which pkg-config) \
      || die "Couldn't configure ffmpeg!"

    # build
    make clean   || die "Couldn't clean ffmpeg!"
    make -j$(($(nproc)-1)) || die "Couldn't build ffmpeg!"
  else
    make
  fi

  make install || die "Couldn't install ffmpeg!"
}

function build_ffmpeg_windows() {
  echo "Building ffmpeg for windows ..."

  #**************************
  # setting

  libs=

  if [[ ! -f config.mak ]]; then
    #------------------------------
    # configure disable and enable

    #------------------------------
    # others

    echo "ffmpeg configure ..."

    if [[ $(uname -s) == *64* ]]; then
      sed -i "s/mingw32/mingw64/g" configure
    fi

    ./configure \
      --prefix=${dist_root} \
      \
      ${FEATURES} \
      \
      --extra-cflags="${CFLAGS}" \
      --extra-cxxflags="${CFLAGS}" \
      \
      --extra-ldflags="${LDFLAGS}" \
      \
      --extra-libs="${libs}" \
      \
      --pkg-config=$(which pkg-config) \
      || die "Couldn't configure ffmpeg!"

    # build
    make clean   || die "Couldn't clean ffmpeg!"
    make -j$(($(nproc)-1)) || die "Couldn't build ffmpeg!"
  else
    make
  fi

  make install || die "Couldn't install ffmpeg!"
}

function build_ffmpeg() {
  echo "Setting up build environment for $platforms $2"

  # set environment variables

  ARCH=$1

  top_root=$PWD

  patch_root=${top_root}/patches

  src_root=${top_root}/out/src

  test -d ${src_root} || mkdir -p ${src_root}

  #**************************
  # unzip archive

  cd $src_root
  if [[ ! -d $ffmpeg_archive_name ]]; then
    tar xvf $ffmpeg_archive
  fi
  src_root=${src_root}/$ffmpeg_archive_name
  cd $src_root

  #**************************
  # calc features

  if grep -q "disable-programs" configure; then
   DISABLE=(${DISABLE[@]}
    programs
   )
  fi

  for i in ${DISABLE[*]}
  do
    FEATURES="${FEATURES} --disable-$i"
  done

  for i in ${ENABLES[*]}
  do
    FEATURES="${FEATURES} --enable-$i"
  done

  #**************************
  # path for build

  if [[ -f VERSION ]]; then
    FF_VER=$(cat VERSION)
  else
    FF_VER=default
  fi

  dist_root=${top_root}/out/$platforms/ffmpeg/${FF_VER}
  #if [[ -n "$ARCH" ]]; then
  #  dist_root=${dist_root}/$ARCH
  #fi

  #rm -rf ${dist_root}

  test -d ${dist_root} || mkdir -p ${dist_root}

  #**************************
  # apply patch

  #patch the configure script to use an Android-friendly versioning scheme
  #patch -u configure ${patch_root}/ffmpeg-configure.patch || die "Couldn't patch ffmpeg configure script!"

  build_ffmpeg_$platforms

  make -f ${in_root}/makefile_for_libffmpeg_so platforms=$platforms

  test -d ${dist_root}/bin || mkdir -p ${dist_root}/bin

  cp libffmpeg.so ${dist_root}/bin
  cp libffmpeg_nostrip.so ${dist_root}/bin

  echo "Build $platforms done, look in ${output_root} for libraries and executables"
}

if [[ "$platforms" == "android" ]]; then
  for ARCH in ${ARCHES}; do
    build_ffmpeg $ARCH
  done
else
  build_ffmpeg
fi

cd ${in_root}
