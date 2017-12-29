#!/bin/bash

shopt -s extglob

cd `dirname $0`

# determine OS and architecture
OS_ARCH=$(uname -sm | tr 'A-Z' 'a-z' | sed "s/\ /\-/g")

# android level
NDK_LEVEL=19

COMPILER=gcc

ffmpeg_archive_name=$(basename $(ls -f ffm*.tar.bz2))
ffmpeg_archive_name="${ffmpeg_archive_name%.tar.bz2}"

if [[ ! -d $ffmpeg_archive_name ]]; then
  tar xf $ffmpeg_archive_name.tar.bz2
fi

#-- error function
function die {
  code=-1
  err="Unknown error!"
  test "$1" && err=$1
  cd ${in_root}
  echo "$err"
  exit -1
}

function build_ffmpeg_android {
  echo "Building ffmpeg for android ..."

  cd $ffmpeg_archive_name

  NDK_ROOT=`which ndk-build`
  NDK_ROOT=`dirname ${NDK_ROOT} 2>/dev/null`

  test -d "${NDK_ROOT}" || die "ndk not found!"

  #**************************
  # apply patch

  #patch the configure script to use an Android-friendly versioning scheme
  #patch -u configure ${patch_root}/ffmpeg-configure.patch || die "Couldn't patch ffmpeg configure script!"

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
  PREFIX=${output_root}

  c_cxx_flags=
  ldflags=
  libs=
  disables=
  enables=

  if [[ "$CPU" == "arm" ]]; then
    c_cxx_flags="${c_cxx_flags} -marm"
  fi
  #c_cxx_flags="${c_cxx_flags} -mthumb"
  #c_cxx_flags="${c_cxx_flags} -fpic"
  #c_cxx_flags="${c_cxx_flags} -ffast-math -fno-tree-vectorize"

  #----------------------
  # ARM Options
  #   https://gcc.gnu.org/onlinedocs/gcc/ARM-Options.html
  
  if [[ "${ARCH}" = "armv5te" ]]; then
    c_cxx_flags="${c_cxx_flags}"
    c_cxx_flags="${c_cxx_flags} -D__ARM_ARCH_5__ -D__ARM_ARCH_5T__ -D__ARM_ARCH_5E__ -D__ARM_ARCH_5TE__"
    c_cxx_flags="${c_cxx_flags} -march=armv5te -mtune=xscale"
  elif [[ "${ARCH}" = "armv7a" ]]; then
    c_cxx_flags="${c_cxx_flags}"
    c_cxx_flags="${c_cxx_flags} -march=armv7-a -mfloat-abi=softfp -mfpu=neon"
    ldflags="${ldflags} -Wl,--fix-cortex-a8"
  else
    die "Unsupport arch ${ARCH}"
  fi

  #------------------------------
  # configure disable and enable

  #disables="${disables} --disable-muxers --disable-encoders"
  #disables="${disables} "

  #enables="${enables} "

  #------------------------------
  # others

  cflags=${c_cxx_flags}
  cxxflags=${c_cxx_flags}

  echo "ffmpeg configure ..."

  ./configure \
    --cross-prefix=${CROSS_PREFIX} \
    --sysroot=${SYSROOT} \
    --prefix=${PREFIX} \
    \
    --arch=${CPU} \
    --target-os=android \
    --enable-cross-compile \
    \
    --enable-shared \
    --disable-static \
    \
    --enable-small \
    --disable-symver \
    \
    --disable-ffplay \
    --disable-ffprobe \
    --disable-ffserver \
    --disable-doc \
    \
    ${disables} \
    ${enables} \
    \
    --extra-cflags="${cflags}" \
    --extra-cxxflags="${cxxflags}" \
    \
    --extra-ldflags="${ldflags}" \
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
  make install || die "Couldn't install ffmpeg!"

  test -d ${dist_include_root}/ffmpeg && rm -rf ${dist_include_root}/ffmpeg
  test -d ${PREFIX}/include && mv ${PREFIX}/include ${dist_include_root}/ffmpeg

  rm -f ${dist_lib_root}/libavcodec*
  rm -f ${dist_lib_root}/libavdevice*
  rm -f ${dist_lib_root}/libavfilter*
  rm -f ${dist_lib_root}/libavformat*
  rm -f ${dist_lib_root}/libavutil*
  rm -f ${dist_lib_root}/libswresample*
  rm -f ${dist_lib_root}/libswscale*

  test -d ${PREFIX}/lib && cp -v ${PREFIX}/lib/lib* ${dist_lib_root}

  test -d ${PREFIX}/bin && cp -vf ${PREFIX}/bin/* ${dist_bin_root}

  cd ${top_root}
}

function build_ffmpeg() {
  echo "Setting up build environment for $1 $2"

  # set environment variables

  ARCH=$2 

  top_root=$PWD

  patch_root=${top_root}/patches

  src_root=${top_root}/$ffmpeg_archive_name

  output_root=${top_root}/out/bin/$1
  dist_root=${top_root}/out/$1
  if [[ -n "$ARCH" ]]; then
    output_root=${output_root}/$ARCH
    dist_root=${dist_root}/$ARCH
  fi
  dist_bin_root=${dist_root}/bin
  dist_lib_root=${dist_root}/lib
  dist_include_root=${dist_root}/include

  # create our folder structure
  test -d ${output_root}       || mkdir -p ${output_root}
  test -d ${dist_bin_root}     || mkdir -p ${dist_bin_root}
  test -d ${dist_include_root} || mkdir -p ${dist_include_root}
  test -d ${dist_lib_root}     || mkdir -p ${dist_lib_root}

  build_ffmpeg_$1

  echo "Build $1 done, look in ${output_root} for libraries and executables"
}

function build_ffmpeg_linux() {
  return 0
}

#ARCHES="armv5te armv7a mips x86_64"
ARCHES="armv7a"

for ARCH in ${ARCHES}; do
  build_ffmpeg android $ARCH
done

#build_ffmpeg linux

cd ${in_root}
