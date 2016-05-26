#!/bin/sh

# $1 = event
# $2 = ref

set -e -u

# $1 = ref
function build {
  git clone git://github.com/elixir-lang/elixir.git --depth 1 --single-branch --branch ${1}

  pushd elixir
  otp $1

  make
  make Precompiled.zip
  aws s3 cp Precompiled*.zip s3://s3.hex.pm/builds/elixir/${1}.zip

  popd
}

# $1 = ref
function delete {
  aws s3 rm s3://s3.hex.pm/builds/elixir/${1}.zip
}

# $1 = ref
function otp {
  rm .tool-versions || true

  otp_version=$(elixir ${cwd}/../../scripts/elixir_to_otp.exs "$1")
  case "${otp_version}" in
    "17")
      echo -e "erlang ref-OTP-17.5.6.9" > .tool-versions
      ;;
    "18")
      echo -e "erlang ref-OTP-18.3.3" > .tool-versions
      ;;
  esac
}

cwd=$(pwd)

case "$1" in
  "push" | "create")
    build $2
    ;;
  "delete")
    delete $2
    ;;
esac
