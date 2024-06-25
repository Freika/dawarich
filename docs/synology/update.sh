#!/bin/sh

author="your name"
URL="https://your.dawarich.domain.com"


if [[ -d spk ]]
then
  rm -rf spk
fi

if [[ -f Dawarich.spk ]]
then
  rm -rf Dawarich.spk
fi

tar -xf spk.tgz

if [[ -f package.tgz ]]
then
  rm -f package.tgz
fi

sed -i "s/maintainer=\"\"/maintainer=\"${author}\"/" spk/INFO
sed -i "s/distributor=\"\"/distributor=\"${author}\"/" spk/INFO
sed -i "s|https://dawarich.my-syno.com|${URL}|" spk/package/ui/config

cd spk/package

tar -czf ../package.tgz *

cd ..

sum=$(md5sum package.tgz | cut -f1 -d" ")

sed -i "s/checksum=\"\"/checksum=\"${sum}\"/" INFO

tar -cf ../Dawarich.spk package.tgz conf scripts INFO PACKAGE_ICON*.PNG

cd ..
