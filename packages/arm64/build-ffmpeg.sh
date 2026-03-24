#!/bin/bash
# Copyright (C) 2025 embedfire
#
# This script is based on work from the FFmpeg project and nyanmisaka's ffmpeg-rockchip repository.
# 本脚本基于FFmpeg项目和nyanmisaka的ffmpeg-rockchip仓库的工作。
#
# FFmpeg is licensed under the GNU Lesser General Public License (LGPL) version 2.1 or later, 
# and the GNU General Public License (GPL) version 2 or later for some parts.
# FFmpeg遵循GNU宽通用公共许可证（LGPL）版本2.1或更高版本，以及对于某些部分的GNU通用公共许可证（GPL）版本2或更高版本。
# See: https://ffmpeg.org/legal.html
# 详见: https://ffmpeg.org/legal.html
#
# The ffmpeg-rockchip repository by nyanmisaka is also licensed under GPLv2 or later.
# nyanmisaka的ffmpeg-rockchip仓库同样根据GPLv2或更高版本许可。
# See: https://github.com/nyanmisaka/ffmpeg-rockchip/blob/master/COPYING.GPLv2
# 详见: https://github.com/nyanmisaka/ffmpeg-rockchip/blob/master/COPYING.GPLv2
#
# By using this script, you agree to abide by the terms of these licenses.
# 通过使用此脚本，您同意遵守这些许可证的条款。
# Build the minimal FFmpeg
cd /tmp
apt-get -y install meson cmake pkg-config gcc libdrm-dev
wget -qO- "https://github.com/nyanmisaka/ffmpeg-rockchip/archive/master.tar.gz" | tar xz
cd ffmpeg-rockchip-master
./configure --prefix=/usr --enable-gpl --enable-version3 --enable-libdrm --enable-rkmpp --enable-rkrga
make -j $(nproc)
# Try the compiled FFmpeg without installation
./ffmpeg -decoders | grep rkmpp
./ffmpeg -encoders | grep rkmpp
./ffmpeg -filters | grep rkrga
# Install FFmpeg to the prefix path
make install
cd ../ && rm -rf ffmpeg-rockchip-master
