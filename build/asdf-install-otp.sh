#!/bin/bash

set -e -u

wget -nv -O otp.tar.gz https://repo.hex.pm/builds/otp/ubuntu-16.04/OTP-${1}.tar.gz
mkdir -p /asdf/installs/erlang/${1}
tar zxf otp.tar.gz -C /asdf/installs/erlang/${1} --strip-components=1
rm otp.tar.gz
/asdf/installs/erlang/${1}/Install -minimal /asdf/installs/erlang/${1}
asdf reshim erlang ${1}
