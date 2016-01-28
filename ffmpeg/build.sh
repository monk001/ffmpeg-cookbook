#!/bin/bash

shopt -s extglob

# fail hard on any error
set -e

ffmpeg_archive_name=ffmpeg-2.8.5

in_root=$PWD

cd `dirname $0`

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

# find / ask for the NDK
echo "Looking for the android ndk root ..."
NDK_ROOT=`which ndk-build`
NDK_ROOT=`dirname ${NDK_ROOT}`
#echo -n "Path to {NDK_ROOT} [${NDK_ROOT}]: "
#read typed_ndk_root
#test "$typed_ndk_root" && {NDK_ROOT}="$typed_ndk_root"

# android level
NDK_LEVEL=19

function build_ffmpeg {
  echo "Building ffmpeg for android ..."

  cd $ffmpeg_archive_name

  #patch the configure script to use an Android-friendly versioning scheme
  #patch -u configure ${patch_root}/ffmpeg-configure.patch || die "Couldn't patch ffmpeg configure script!"

  SYSROOT=${NDK_ROOT}/platforms/android-${NDK_LEVEL}/arch-${CPU}
  TOOLCHAIN=$(ls -d ${NDK_ROOT}/toolchains/${CPU}-linux-androideabi-[0-9]* | sort -r | head -1)/prebuilt/${OS_ARCH}
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
    m_c_cxx_flags="${m_c_cxx_flags} -DHAVE_NEON=0"
    m_c_cxx_flags="${m_c_cxx_flags} -D__ARM_ARCH_5__ -D__ARM_ARCH_5T__ -D__ARM_ARCH_5E__ -D__ARM_ARCH_5TE__"
    m_c_cxx_flags="${m_c_cxx_flags} -march=armv5te -mtune=xscale"
  elif [[ "${ARCH}" = "armv7a" ]]; then
    m_c_cxx_flags="${m_c_cxx_flags} -DHAVE_NEON=1"
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
  make -j6     || die "Couldn't build ffmpeg!"
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

function build() {
  echo "Setting up build environment for $1 ..."

  # set environment variables
  top_root=$PWD
  src_root=${top_root}/$ffmpeg_archive_name
  patch_root=${top_root}/patches
  output_root=${top_root}/out/${ARCH}
  dist_root=${top_root}
  dist_bin_root=${dist_root}/bin/${ARCH}
  dist_include_root=${dist_root}/include
  dist_lib_root=${dist_root}/lib/${ARCH}

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

  build_$1

  echo "Build $1 done, look in ${output_root} for libraries and executables (${ARCH})."
}

#ARCHES="armv5te armv7a mips x86"
ARCHES="armv5te armv7a"

for ARCH in ${ARCHES}; do
  build ffmpeg 
done

cd ${in_root}
