#!/bin/bash

set -euox pipefail

if [ -z "${OTP_REF}" ]; then
  echo "OTP_REF not set"
  exit 1
fi

echo "Building OTP_REF ${OTP_REF}"
otp_url=https://github.com/erlang/otp/archive/${OTP_SHA}.tar.gz
otp_tar_name=$(basename "${otp_url}")
otp_untar_dir="otp-${OTP_SHA}"

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
make -j$(getconf _NPROCESSORS_ONLN) release

if [ "${OTP_REF:0:3}" = "OTP" ] && [ "${OTP_REF:4:2}" -ge "23" ]; then
  make -j$(getconf _NPROCESSORS_ONLN) release_docs DOC_TARGETS="chunks"
fi

cd ../
mv "${otp_untar_dir}"/release/*/ "${OTP_REF}"
rm "${otp_tar_name}"
tar -zcf out/${OTP_REF}.tar.gz ${OTP_REF}
