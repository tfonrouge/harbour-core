#!/usr/bin/env bash

# ---------------------------------------------------------------
# Copyright 2017 Viktor Szakats (vszakats.net/harbour)
# See LICENSE.txt for licensing terms.
# ---------------------------------------------------------------

# for Linux Amazon

set -x; cat /etc/*-release; ulimit -a; df -h

yum install -y gcc git rpm-build findutils \
  cairo-devel \
  cups-devel \
  curl-devel \
  expat-devel \
  file-libs \
  firebird-devel \
  freeimage-devel \
  gd-devel \
  ghostscript-devel \
  libmariadb-devel \
  libyaml-devel \
  lzo-devel \
  minizip-devel \
  openssl-devel \
  postgresql-devel \
  unixODBC-devel

# librabbitmq-devel provides verison 0.2, which is too old to
# be supported.

./package/mpkg_rpm.sh

ls -l ./package/RPM/RPMS/x86_64/
