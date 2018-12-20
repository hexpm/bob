#!/bin/bash

set -euox pipefail

if [ -z "${OTP_REF}" ]; then
  echo "OTP_REF not set"
  exit 1
fi

echo "Building OTP_REF ${OTP_REF}"
otp_url=https://github.com/erlang/otp/archive/${OTP_REF}.tar.gz
otp_tar_name=$(basename https://github.com/erlang/otp/archive/${OTP_REF}.tar.gz)
otp_untar_dir="otp-${OTP_REF}"

wget -nv ${otp_url}
echo "******====*******"
ls
echo "******====*******"
tar -zxf ${otp_tar_name}
chmod -R 777 ${otp_untar_dir}

cd ${otp_untar_dir}

./otp_build autoconf
./configure \
  --without-javac \
  --without-wx \
  --without-debugger \
  --without-observer \
  --without-jinterface \
  --without-cosEvent\
  --without-cosEventDomain \
  --without-cosFileTransfer \
  --without-cosNotification \
  --without-cosProperty \
  --without-cosTime \
  --without-cosTransactions \
  --without-et \
  --without-gs \
  --without-ic \
  --without-megaco \
  --without-orber \
  --without-percept \
  --without-typer \
  --with-ssl \
  --enable-threads \
  --enable-dirty-schedulers

make -j4
make release

cd ../
mv otp-${OTP_REF}/release/x86_64-unknown-linux-gnu/ ${OTP_REF}
rm ${OTP_REF}.tar.gz
tar -zcf out/${OTP_REF}.tar.gz ${OTP_REF}
