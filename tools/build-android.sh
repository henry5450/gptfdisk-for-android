#!/bin/sh
#
# Build native Android executables of gptfdisk with the Android NDK.
#
# Usage:
#   tools/build-android.sh [--abi arm64-v8a] [--api 24] [--ndk /path/to/ndk]
#
# The build needs two third-party libraries that bionic does not provide in a
# linkable form:
#   popt 1.19     - command-line parsing (sgdisk)
#   ncurses 6.5   - curses UI (cgdisk)
# They are downloaded, cross-compiled, and installed under
# android/deps/<abi>/ on first run; downloads and build trees live in
# tmp/android-build/.  Binaries are written to dist/android-<abi>/ and
# stripped with the NDK's llvm-strip.
#
# gptfdisk is licensed under the GPL v2 or later; see COPYING.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD="$ROOT/tmp/android-build"

ABI=arm64-v8a
API=24
NDK=${NDK:-}

usage() {
   echo "Usage: $0 [--abi arm64-v8a|armeabi-v7a|x86_64] [--api 24] [--ndk DIR]" >&2
   exit 1
}

while [ $# -gt 0 ]; do
   case $1 in
      --abi) ABI=$2; shift 2 ;;
      --api) API=$2; shift 2 ;;
      --ndk) NDK=$2; shift 2 ;;
      -h|--help) usage ;;
      *) usage ;;
   esac
done

case $ABI in
   arm64-v8a)        ANDROID_TARGET=aarch64-linux-android ;;
   armeabi-v7a)      ANDROID_TARGET=armv7a-linux-androideabi ;;
   x86_64)           ANDROID_TARGET=x86_64-linux-android ;;
   *) echo "Unsupported ABI: $ABI" >&2; exit 1 ;;
esac

# Locate the NDK if it was not given explicitly.
if [ -z "$NDK" ]; then
   for candidate in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}" \
                    "${HOME:-}/Android/Sdk/ndk/"* \
                    /opt/android-ndk* /Application/android-ndk*; do
      if [ -n "$candidate" ] && [ -d "$candidate/toolchains/llvm" ]; then
         NDK=$candidate
         break
      fi
   done
fi
if [ -z "$NDK" ] || [ ! -d "$NDK/toolchains/llvm" ]; then
   echo "Android NDK not found; pass --ndk /path/to/android-ndk" >&2
   exit 1
fi

# The NDK ships one prebuilt toolchain per host; use the first available.
for tc in "$NDK"/toolchains/llvm/prebuilt/*/; do
   [ -d "$tc" ] && TOOLCHAIN=$tc && break
done
if [ -z "${TOOLCHAIN:-}" ]; then
   echo "No prebuilt LLVM toolchain found under $NDK" >&2
   exit 1
fi
TC=$TOOLCHAIN/bin
CC=$TC/$ANDROID_TARGET$API-clang
CXX=$TC/$ANDROID_TARGET$API-clang++
AR=$TC/llvm-ar
RANLIB=$TC/llvm-ranlib
STRIP=$TC/llvm-strip

PREFIX="$ROOT/android/deps/$ABI"
mkdir -p "$BUILD" "$PREFIX"

POPT_URL=https://deb.debian.org/debian/pool/main/p/popt/popt_1.19+dfsg.orig.tar.xz
POPT_SHA=4cd0cd2963d0c4078f65949599d97135c15ee6c09cf3a36a9a1b2753025bb06b
NCURSES_URL=https://deb.debian.org/debian/pool/main/n/ncurses/ncurses_6.5+20250216.orig.tar.gz
NCURSES_SHA=b37baafa436e7133bb12a185cb8f60e1599b1947e9f0181c76f3190acf28b6eb

fetch() {
   url=$1
   out=$2
   if [ ! -f "$out" ]; then
      echo "Downloading $url"
      if command -v curl >/dev/null 2>&1; then
         curl -fL --retry 3 -o "$out.part" "$url"
      else
         wget -O "$out.part" "$url"
      fi
      mv "$out.part" "$out"
   fi
}

check_sha() {
   file=$1
   want=$2
   have=$(sha256sum "$file" | cut -d' ' -f1)
   if [ "$have" != "$want" ]; then
      echo "Checksum mismatch for $file" >&2
      exit 1
   fi
}

extract() {
   archive=$1
   case $archive in
      *.tar.xz) tar xJf "$archive" -C "$BUILD" ;;
      *.tar.gz) tar xzf "$archive" -C "$BUILD" ;;
   esac
}

# Cross-compile popt if it is not already installed for this ABI.
if [ ! -f "$PREFIX/lib/libpopt.a" ]; then
   fetch "$POPT_URL" "$BUILD/popt-1.19.tar.xz"
   check_sha "$BUILD/popt-1.19.tar.xz" "$POPT_SHA"
   extract "$BUILD/popt-1.19.tar.xz"
   echo "Building popt for $ABI"
   (
      cd "$BUILD/popt-1.19"
      ./configure --host="$ANDROID_TARGET" --prefix="$PREFIX" --sysconfdir=/etc \
         CC="$CC" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP" \
         CFLAGS="-O2 -fPIE" ac_cv_header_glob_h=no \
         --disable-nls --disable-shared --enable-static
      make -j"$(nproc 2>/dev/null || echo 2)"
      make install
   )
fi

# Cross-compile ncursesw if it is not already installed for this ABI.
if [ ! -f "$PREFIX/lib/libncursesw.a" ]; then
   fetch "$NCURSES_URL" "$BUILD/ncurses.tar.gz"
   check_sha "$BUILD/ncurses.tar.gz" "$NCURSES_SHA"
   extract "$BUILD/ncurses.tar.gz"
   for dir in "$BUILD"/ncurses-*/; do
      [ -f "$dir/configure" ] && NCURSES_SRC=$dir && break
   done
   echo "Building ncursesw for $ABI"
   (
      cd "${NCURSES_SRC:?ncurses source tree not found}"
      ./configure --host="$ANDROID_TARGET" --prefix="$PREFIX" \
         CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP" \
         CFLAGS="-O2 -fPIE" CXXFLAGS="-O2 -fPIE" \
         --enable-widec --without-shared --with-normal --without-debug \
         --without-manpages --without-progs --without-tests --without-ada \
         --disable-stripping \
         --with-fallbacks=xterm,xterm-256color,screen,screen-256color,vt100,linux,ansi
      make -j"$(nproc 2>/dev/null || echo 2)"
      make install
   )
fi

# Build the programs.
cd "$ROOT"
JOBS=$(nproc 2>/dev/null || echo 2)
make TARGET=android NDK="$NDK" ANDROID_ABI="$ABI" ANDROID_API="$API" \
   ANDROID_PREFIX="$PREFIX" clean
make TARGET=android NDK="$NDK" ANDROID_ABI="$ABI" ANDROID_API="$API" \
   ANDROID_PREFIX="$PREFIX" -j"$JOBS"

OUT="$ROOT/dist/android-$ABI"
mkdir -p "$OUT"
for tool in gdisk cgdisk sgdisk fixparts; do
   cp "$ROOT/$tool" "$OUT/$tool"
   "$STRIP" "$OUT/$tool"
done

echo
echo "Built for $ABI (API $API):"
ls -l "$OUT"
