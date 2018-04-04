#!/bin/bash

set -e -u

version=$1
linux=$2

wget -nv -O otp.tar.gz https://repo.hex.pm/builds/otp/${linux}/OTP-${version}.tar.gz
mkdir -p /asdf/installs/erlang/${version}
tar zxf otp.tar.gz -C /asdf/installs/erlang/${version} --strip-components=1
rm otp.tar.gz
/asdf/installs/erlang/${version}/Install -minimal /asdf/installs/erlang/${version}
asdf reshim erlang ${version}
