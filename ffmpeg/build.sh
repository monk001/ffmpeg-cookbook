#!/bin/bash

shopt -s extglob

# fail hard on any error
set -e

in_root=$PWD

cd `dirname $0`

ffmpeg_archive_name=$(basename $(ls -f ffm*.tar.bz2))
ffmpeg_archive_name="${ffmpeg_archive_name%.tar.bz2}"

if [[ ! -d $ffmpeg_archive_name ]]; then
  tar jxvf $ffmpeg_archive_name.tar.bz2
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

# determine OS and architecture
OS_ARCH=$(uname -sm | tr 'A-Z' 'a-z' | sed "s/\ /\-/g")

# android level
NDK_LEVEL=19

function build_ffmpeg_android {
  echo "Building ffmpeg for android ..."

  cd $ffmpeg_archive_name

  NDK_ROOT=`which ndk-build`
  NDK_ROOT=`dirname ${NDK_ROOT}`

  #patch the configure script to use an Android-friendly versioning scheme
  #patch -u configure ${patch_root}/ffmpeg-configure.patch || die "Couldn't patch ffmpeg configure script!"

  if [[ "$CPU" == "arm" ]]; then
    TOOLCHAIN_NAME=arm-linux-androideabi
  elif [[ "$CPU" == "x86" ]]; then
    TOOLCHAIN_NAME=x86
  fi

  TOOLCHAIN=$(ls -d ${NDK_ROOT}/toolchains/${TOOLCHAIN_NAME}-[0-9].* | sort -r | head -1)/prebuilt/${OS_ARCH}
  SYSROOT=${NDK_ROOT}/platforms/android-${NDK_LEVEL}/arch-${CPU}
  PREFIX=${output_root}

  #**************************
  # configure setting

  m_c_cxx_flags=
  m_ldflags=
  m_libs=
  m_disables=
  m_enables=

  m_c_cxx_flags="${m_c_cxx_flags} -marm"
  #m_c_cxx_flags="${m_c_cxx_flags} -mthumb"
  #m_c_cxx_flags="${m_c_cxx_flags} -fpic"
  #m_c_cxx_flags="${m_c_cxx_flags} -ffast-math -fno-tree-vectorize"

  #----------------------
  # ARM Options
  #   https://gcc.gnu.org/onlinedocs/gcc/ARM-Options.html
  
  if [[ "${ARCH}" = "armv5te" ]]; then
    m_c_cxx_flags="${m_c_cxx_flags}"
    m_c_cxx_flags="${m_c_cxx_flags} -D__ARM_ARCH_5__ -D__ARM_ARCH_5T__ -D__ARM_ARCH_5E__ -D__ARM_ARCH_5TE__"
    m_c_cxx_flags="${m_c_cxx_flags} -march=armv5te -mtune=xscale"
  elif [[ "${ARCH}" = "armv7a" ]]; then
    m_c_cxx_flags="${m_c_cxx_flags}"
    m_c_cxx_flags="${m_c_cxx_flags} -march=armv7-a -mfloat-abi=softfp -mfpu=neon"
    m_ldflags="${m_ldflags} -Wl,--fix-cortex-a8"
  else
    die "Unsupport arch ${ARCH}"
  fi

  #------------------------------
  # configure disable and enable

  #m_disables="${m_disables} --disable-muxers --disable-encoders"
  #m_disables="${m_disables} "

  #m_enables="${m_enables} "

  #------------------------------
  # others

  m_cflags=${m_c_cxx_flags}
  m_cxxflags=${m_c_cxx_flags}

  echo "ffmpeg configure ..."

  ./configure \
    --cross-prefix=${TOOLCHAIN}/bin/${CPU}-linux-androideabi- \
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
    --disable-ffmpeg \
    --disable-ffplay \
    --disable-ffprobe \
    --disable-ffserver \
    --disable-doc \
    \
    ${m_disables} \
    ${m_enables} \
    \
    --extra-cflags="${m_cflags}" \
    --extra-cxxflags="${m_cxxflags}" \
    \
    --extra-ldflags="${m_ldflags}" \
    \
    --extra-libs="${m_libs}" \
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

  ARCH=$2

  # set environment variables
  top_root=$PWD
  patch_root=${top_root}/patches
  src_root=${top_root}/$ffmpeg_archive_name
  dist_root=${top_root}/$1
  output_root=${top_root}/out/$1

  dist_bin_root=${dist_root}/bin
  dist_lib_root=${dist_root}/lib
  dist_include_root=${dist_root}/include

  if [[ -n "$1" ]]; then
    output_root=${output_root}/${ARCH}
    dist_bin_root=${dist_bin_root}/${ARCH}
    dist_lib_root=${dist_lib_root}/${ARCH}
    dist_include_root=${dist_include_root}/${ARCH}
  fi

  # create our folder structure
  test -d ${src_root}          || mkdir -p ${src_root}
  test -d ${output_root}       || mkdir -p ${output_root}
  test -d ${dist_bin_root}     || mkdir -p ${dist_bin_root}
  test -d ${dist_include_root} || mkdir -p ${dist_include_root}
  test -d ${dist_lib_root}     || mkdir -p ${dist_lib_root}

  if [[ ${ARCH} = arm* ]]; then
    CPU=arm
  else
    CPU=${ARCH}
  fi

  build_ffmpeg_$1

  echo "Build $1 done, look in ${output_root} for libraries and executables (${ARCH})."
}

function build_ffmpeg_linux() {
  return 0
}

#ARCHES="armv5te armv7a mips x86"
ARCHES="armv5te armv7a"

#for ARCH in ${ARCHES}; do
#  build_ffmpeg android $ARCH
#done

build_ffmpeg linux

cd ${in_root}
