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
tar -zxf ${otp_tar_name}
chmod -R 777 ${otp_untar_dir}

cd ${otp_untar_dir}

./otp_build autoconf

# Work around "LD: multiple definition of" errors on GCC 10, issue fixed in OTP 22.3
if [ "${UBUNTU_VERSION}" = "20.04" ]; then
  if [ "${OTP_REF:0:5}" = "OTP-1" ] || [ "${OTP_REF:0:6}" = "OTP-20" ] || [ "${OTP_REF:0:6}" = "OTP-21" ] || [ "${OTP_REF:0:6}" = "OTP-22" ]; then
    CC=gcc-9 ./configure --with-ssl --enable-dirty-schedulers
  else
    ./configure --with-ssl --enable-dirty-schedulers
  fi
else
  ./configure --with-ssl --enable-dirty-schedulers
fi

make -j$(getconf _NPROCESSORS_ONLN)
make release

if [ "${OTP_REF:0:3}" = "OTP" ] && [ "${OTP_REF:4:2}" -ge "23" ]; then
  make release_docs DOC_TARGETS="chunks"
fi

cd ../
mv otp-${OTP_REF}/release/*/ ${OTP_REF}
rm ${OTP_REF}.tar.gz
tar -zcf out/${OTP_REF}.tar.gz ${OTP_REF}
