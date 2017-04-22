#!/bin/sh

# ---------------------------------------------------------------
# Copyright 2015-2017 Viktor Szakats (vszakats.net/harbour)
# See LICENSE.txt for licensing terms.
# ---------------------------------------------------------------

[ -n "${CI}" ] || [ "$1" = '--force' ] || exit

cd "$(dirname "$0")/.." || exit

case "$(uname)" in
  *_NT*)   readonly os='win';;
  Linux*)  readonly os='linux';;
  Darwin*) readonly os='mac';;
  *BSD)    readonly os='bsd';;
esac

_BRANCH="${APPVEYOR_REPO_BRANCH}${TRAVIS_BRANCH}${CI_BUILD_REF_NAME}${GIT_BRANCH}"
[ -n "${_BRANCH}" ] || _BRANCH="$(git symbolic-ref --short --quiet HEAD)"
[ -n "${_BRANCH}" ] || _BRANCH='master'
_BRANC4="$(echo "${_BRANCH}" | cut -c -4)"

[ -n "${HB_CI_THREADS}" ] || HB_CI_THREADS=4

_ROOT="$(realpath '.')"

# Don't remove these markers.
#hashbegin
export NGHTTP2_VER='1.21.1'
export NGHTTP2_HASH_32='bc453759de4498640d4a99e0c56f5cf785ecdc8c3a2a83b4c3d11f6d62b40160'
export NGHTTP2_HASH_64='d68047214f5499de5722da1b5b55cc4be008e4bb9e568c4e3234e8811730cea4'
export OPENSSL_VER='1.1.0e'
export OPENSSL_HASH_32='f45bb7a8c246d8b0a09404c3e11783a721de2d7bad3697909358427aefd58b49'
export OPENSSL_HASH_64='2318903035004446115ab714145497d5a015a1d4f0a99b8f8c75636ce6e4730b'
export LIBSSH2_VER='1.8.0'
export LIBSSH2_HASH_32='ea6b8ed1a2e9224fb041c620b9364a0888d9a874764c48edcd6818bf2597bd71'
export LIBSSH2_HASH_64='2a6b25c04082f3b206d7e05c72237eeba10e7b1b68a2c1bfbaef03589ce64733'
export CURL_VER='7.54.0'
export CURL_HASH_32='d65fb418b56f60db69358e95cb463f17ed4a11572195776c9c84c807b75245e1'
export CURL_HASH_64='bca3faf3cf8b1ccda58dbf43f98f8335f9aaef8bea64979ce790f544597056df'
#hashend

# Install/update MSYS2 packages required for completing the build

echo "! TZ: $(date +%Z) | ${TZ}"
echo "! LANG: ${LANG}"
echo "! LC_ALL: ${LC_ALL}"
echo "! LC_CTYPE: ${LC_CTYPE}"

case "${os}" in
  win)
    pacman --noconfirm --noprogressbar -S --needed p7zip mingw-w64-{i686,x86_64}-{jq,osslsigncode}
    # Dependencies for cross-builds:
    #   http://pkg.mxe.cc/repos/
    ;;
  mac)
    # Required:
    #   brew install p7zip mingw-w64 jq osslsigncode dos2unix gpg coreutils wine
    # - `wine` for running `harbour.exe` when creating `BUILD.txt` and
    #   `HB_BUILD_POSTRUN` tasks
    # - `coreutils` for `gcp`.
    #   TODO: replace it with `rsync` where `--parents` option is used.
    _mxe="${HOME}/mxe"
    ;;
  linux)
    # Required:
    #   binutils-mingw-w64 gcc-mingw-w64 g++-mingw-w64 p7zip-full jq dos2unix realpath osslsigncode wine gnupg-curl
    _mxe="/usr/lib/mxe"
    ;;
esac

if [ "${os}" != 'win' ]; then

  # msvc only available on Windows
  [ "${_BRANC4}" != 'msvc' ] || exit

  # Create native build for host OS
  make -j "${HB_CI_THREADS}" HB_BUILD_DYN=no HB_BUILD_CONTRIBS=hbdoc
fi

"$(dirname "$0")/mpkg_win_dl.sh" || exit

export HB_VF='snapshot'
export HB_RT="${_ROOT}"
export HB_MKFLAGS="HB_VERSION=${HB_VF}"
export HB_BASE='64'
_ori_path="${PATH}"

if [ -n "${HB_CI_THREADS}" ]; then
  export HB_MKFLAGS="${HB_MKFLAGS} -j ${HB_CI_THREADS}"
fi

# common settings

# Clean slate
unset HB_CCPREFIX
unset HB_CCSUFFIX
unset HB_BUILD_CONTRIBS
unset HB_USER_CFLAGS
unset HB_USER_LDFLAGS
unset HB_USER_DFLAGS

_HB_USER_CFLAGS=''

[ "${_BRANCH#*prod*}" != "${_BRANCH}" ] && export HB_BUILD_CONTRIBS='hbrun hbdoc hbformat/utils hbct hbcurl hbhpdf hbmzip hbwin hbtip hbssl hbexpat hbmemio rddsql hbzebra sddodbc hbunix hbmisc hbcups hbtest hbtcpio hbcomio hbcrypto hbnetio hbpipeio hbgzio hbbz2io hbicu'
export HB_BUILD_STRIP='bin'
export HB_BUILD_PKG='yes'
export _HB_BUILD_PKG_ARCHIVE='no'

# can disable to save time/space

[ "${_BRANC4}" = 'msvc' ] || export _HB_BUNDLE_3RDLIB='yes'
export HB_INSTALL_3RDDYN='yes'
export HB_BUILD_CONTRIB_DYN='yes'
export HB_BUILD_POSTRUN='"./hbmk2 --version" "./hbrun --version" "./hbtest -noenv" "./hbspeed --noenv --stdout"'

# debug

# export HB_BUILD_CONTRIBS='no'
# export HB_MKFLAGS="${HB_MKFLAGS} HB_BUILD_OPTIM=no"
# export HB_BUILD_VERBOSE='yes'
# export _HB_PKG_DEBUG='yes'
# export _HB_BUNDLE_3RDLIB='yes'

# decrypt code signing key

CODESIGN_KEY="$(realpath './package')/vszakats.p12"
(
  set +x
  if [ -n "${HB_CODESIGN_GPG_PASS}" ]; then
    gpg --batch --passphrase "${HB_CODESIGN_GPG_PASS}" -o "${CODESIGN_KEY}" -d "${CODESIGN_KEY}.asc"
  fi
)
[ -f "${CODESIGN_KEY}" ] || unset CODESIGN_KEY

# mingw

if [ "${_BRANC4}" != 'msvc' ]; then

  # LTO is broken as of mingw 6.1.0
# [ "${_BRANCH#*prod*}" != "${_BRANCH}" ] && _HB_USER_CFLAGS="${_HB_USER_CFLAGS} -flto -ffat-lto-objects"
  [ "${HB_BUILD_MODE}" = 'cpp' ] && export HB_USER_LDFLAGS="${HB_USER_LDFLAGS} -static-libstdc++"

  if [ "${os}" = 'win' ]; then
    readonly _msys_mingw32='/mingw32'
    readonly _msys_mingw64='/mingw64'

    export HB_DIR_MINGW_64="${HB_RT}/mingw64/bin/"
    if [ -d "${HB_DIR_MINGW_64}" ]; then
      # Use the same toolchain for both targets
      export HB_DIR_MINGW_32="${HB_DIR_MINGW_64}"
      _build_info_32='BUILD-mingw.txt'
      _build_info_64=/dev/null
    else
      export HB_DIR_MINGW_32="${_msys_mingw32}/bin/"
      export HB_DIR_MINGW_64="${_msys_mingw64}/bin/"
      _build_info_32='BUILD-mingw32.txt'
      _build_info_64='BUILD-mingw64.txt'
    fi
    export HB_PFX_MINGW_32=
    export HB_PFX_MINGW_64=
    _bin_make='mingw32-make'

    # Disable picking MSYS2 packages for now
    export HB_BUILD_3RDEXT='no'
  else
    export HB_PFX_MINGW_32='i686-w64-mingw32-'
    export HB_PFX_MINGW_64='x86_64-w64-mingw32-'
    export HB_DIR_MINGW_32=
    export HB_DIR_MINGW_64=
    HB_DIR_MINGW_32="$(dirname "$(which ${HB_PFX_MINGW_32}gcc)")"/
    HB_DIR_MINGW_64="$(dirname "$(which ${HB_PFX_MINGW_64}gcc)")"/
    _build_info_32='BUILD-mingw32.txt'
    _build_info_64='BUILD-mingw64.txt'
    _bin_make='make'

    export HB_BUILD_3RDEXT='no'
  fi

  export HB_DIR_OPENSSL_32="${HB_RT}/openssl-mingw32/"
  export HB_DIR_OPENSSL_64="${HB_RT}/openssl-mingw64/"
  export HB_DIR_LIBSSH2_32="${HB_RT}/libssh2-mingw32/"
  export HB_DIR_LIBSSH2_64="${HB_RT}/libssh2-mingw64/"
  export HB_DIR_NGHTTP2_32="${HB_RT}/nghttp2-mingw32/"
  export HB_DIR_NGHTTP2_64="${HB_RT}/nghttp2-mingw64/"
  export HB_DIR_CURL_32="${HB_RT}/curl-mingw32/"
  export HB_DIR_CURL_64="${HB_RT}/curl-mingw64/"

  #
  export HB_WITH_CURL="${HB_DIR_CURL_32}include"
  export HB_WITH_OPENSSL="${HB_DIR_OPENSSL_32}include"
  unset _inc_df _libdir
  if [ "${os}" = 'win' ]; then
    _inc_df="${_msys_mingw32}/include"
    export HB_WITH_GS_BIN="${_inc_df}/../bin"
    export HB_WITH_MYSQL="${_inc_df}/mysql"
  elif [ -d "${_mxe}/usr/i686-w64-mingw32.shared/include" ]; then
    _inc_df="${_mxe}/usr/i686-w64-mingw32.shared/include"
    _libdir="${_mxe}/usr/i686-w64-mingw32.shared/lib"
    export HB_WITH_LIBMAGIC="${_inc_df}"
    export HB_WITH_MYSQL="${_inc_df}"
    export HB_STATIC_FREEIMAGE=yes
    export HB_STATIC_GD=yes
  fi
  if [ -d "${_mxe}/usr/i686-w64-mingw32.static/include" ]; then
    _inc_st="${_mxe}/usr/i686-w64-mingw32.static/include"
    _libdir="${_libdir};${_mxe}/usr/i686-w64-mingw32.static/lib"
  else
    _inc_st="${_inc_df}"
  fi
  if [ -n "${_inc_df}" ]; then
    export HB_WITH_CAIRO="${_inc_df}/cairo"
    export HB_WITH_FREEIMAGE="${_inc_st}"
    export HB_WITH_GD="${_inc_st}"
    # FIXME: Because mxe ghostscript packages misses a binary, version detection
    #        falls back to using the native ghostscript package. Applies to
    #        64-bit as well.
    export HB_WITH_GS="${_inc_df}/ghostscript"
    export HB_WITH_ICU="${_inc_df}"
    export HB_WITH_PGSQL="${_inc_df}"
  fi
  printenv | grep -E '^(HB_WITH_|HBMK_WITH_)' | sort
  unset HB_USER_CFLAGS
  [ -n "${_HB_USER_CFLAGS}" ] && export HB_USER_CFLAGS="${_HB_USER_CFLAGS}"
  unset HB_BUILD_LIBPATH
  [ -n "${_libdir}" ] && export HB_BUILD_LIBPATH="${_libdir}"
  export HB_CCPREFIX="${HB_PFX_MINGW_32}"
  [ "${HB_BUILD_MODE}" != 'cpp' ] && export HB_USER_CFLAGS="${HB_USER_CFLAGS} -fno-asynchronous-unwind-tables"
  [ "${os}" = 'win' ] && export PATH="${HB_DIR_MINGW_32}:${_ori_path}"
  ${HB_CCPREFIX}gcc -v 2>&1 | tee "${_build_info_32}"
  if which osslsigncode > /dev/null 2>&1; then
    export HB_CODESIGN_KEY="${CODESIGN_KEY}"
  else
    unset HB_CODESIGN_KEY
  fi
  # shellcheck disable=SC2086
  ${_bin_make} install ${HB_MKFLAGS} HB_COMPILER=mingw HB_CPU=x86 || exit 1

  export HB_WITH_CURL="${HB_DIR_CURL_64}include"
  export HB_WITH_OPENSSL="${HB_DIR_OPENSSL_64}include"
  unset _inc_df _libdir
  if [ "${os}" = 'win' ]; then
    _inc_df="${_msys_mingw64}/include"
    export HB_WITH_GS_BIN="${_inc_df}/../bin"
    export HB_WITH_MYSQL="${_inc_df}/mysql"
  elif [ -d "${_mxe}/usr/x86_64-w64-mingw32.shared/include" ]; then
    _inc_df="${_mxe}/usr/x86_64-w64-mingw32.shared/include"
    _libdir="${_mxe}/usr/x86_64-w64-mingw32.shared/lib"
    export HB_WITH_LIBMAGIC="${_inc_df}"
    export HB_WITH_MYSQL="${_inc_df}"
    export HB_STATIC_FREEIMAGE=yes
    export HB_STATIC_GD=yes
  fi
  if [ -d "${_mxe}/usr/x86_64-w64-mingw32.static/include" ]; then
    _inc_st="${_mxe}/usr/x86_64-w64-mingw32.static/include"
    _libdir="${_libdir};${_mxe}/usr/x86_64-w64-mingw32.static/lib"
  else
    _inc_st="${_inc_df}"
  fi
  if [ -n "${_inc_df}" ]; then
    export HB_WITH_CAIRO="${_inc_df}/cairo"
    export HB_WITH_FREEIMAGE="${_inc_st}"
    export HB_WITH_GD="${_inc_st}"
    export HB_WITH_GS="${_inc_df}/ghostscript"
    export HB_WITH_ICU="${_inc_df}"
    export HB_WITH_PGSQL="${_inc_df}"
  fi
  printenv | grep -E '^(HB_WITH_|HBMK_WITH_)' | sort
  unset HB_USER_CFLAGS
  [ -n "${_HB_USER_CFLAGS}" ] && export HB_USER_CFLAGS="${_HB_USER_CFLAGS}"
  unset HB_BUILD_LIBPATH
  [ -n "${_libdir}" ] && export HB_BUILD_LIBPATH="${_libdir}"
  export HB_CCPREFIX="${HB_PFX_MINGW_64}"
  [ "${os}" = 'win' ] && export PATH="${HB_DIR_MINGW_64}:${_ori_path}"
  ${HB_CCPREFIX}gcc -v 2>&1 | tee "${_build_info_64}"
  if which osslsigncode > /dev/null 2>&1; then
    export HB_CODESIGN_KEY="${CODESIGN_KEY}"
  else
    unset HB_CODESIGN_KEY
  fi
  # shellcheck disable=SC2086
  ${_bin_make} install ${HB_MKFLAGS} HB_COMPILER=mingw64 HB_CPU=x86_64 || exit 1
fi

# msvc

if [ "${_BRANC4}" = 'msvc' ]; then

  export PATH="${_ori_path}"

  unset HB_USER_CFLAGS
  unset HB_USER_LDFLAGS
  unset HB_USER_DFLAGS
  unset HB_WITH_CURL
  unset HB_WITH_OPENSSL
  # FIXME: clear all HB_WITH_ variables

# export _HB_MSVC_ANALYZE='yes'

  [ "${_BRANCH}" = 'msvc2008' ] && _VCVARSALL=' 9.0\VC'
  [ "${_BRANCH}" = 'msvc2010' ] && _VCVARSALL=' 10.0\VC'
  [ "${_BRANCH}" = 'msvc2012' ] && _VCVARSALL=' 11.0\VC'
  [ "${_BRANCH}" = 'msvc2013' ] && _VCVARSALL=' 12.0\VC'
  [ "${_BRANCH}" = 'msvc2015' ] && _VCVARSALL=' 14.0\VC'
  [ "${_BRANCH}" = 'msvc2017' ] && _VCVARSALL='\2017\Community\VC\Auxiliary\Build'

  export _VCVARSALL="%ProgramFiles(x86)%\Microsoft Visual Studio${_VCVARSALL}\vcvarsall.bat"

  if [ -n "${_VCVARSALL}" ]; then
    cat << EOF > _make.bat
      call "${_VCVARSALL}" x86
      C:\msys64\mingw64\bin\mingw32-make.exe install %HB_MKFLAGS% HB_COMPILER=msvc
EOF
    ./_make.bat
    rm _make.bat
  fi

  # 64-bit target not supported by these MSVC versions
  [ "${_BRANCH}" = 'msvc2008' ] && _VCVARSALL=
  [ "${_BRANCH}" = 'msvc2010' ] && _VCVARSALL=

  if [ -n "${_VCVARSALL}" ]; then
    cat << EOF > _make.bat
      call "${_VCVARSALL}" x86_amd64
      C:\msys64\mingw64\bin\mingw32-make.exe install %HB_MKFLAGS% HB_COMPILER=msvc64
EOF
    ./_make.bat
    rm _make.bat
  fi
fi

# packaging

[ "${_BRANC4}" = 'msvc' ] || "$(dirname "$0")/mpkg_win.sh"

# documentation

"$(dirname "$0")/upd_doc.sh" "${_BRANCH}"
