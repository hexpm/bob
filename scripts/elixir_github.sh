#!/bin/bash

# $1 = event
# $2 = ref

set -e -u

function fastly_purge {
  curl \
    -X POST \
    -H "Fastly-Key: ${BOB_FASTLY_KEY}" \
    -H "Accept: application/json" \
    -H "Content-Length: 0" \
    "https://api.fastly.com/service/${BOB_FASTLY_SERVICE}/purge/builds"
}

# $1 = ref
function build {
  git clone git://github.com/elixir-lang/elixir.git --depth 1 --single-branch --branch ${1}

  pushd elixir
  otp $1
  erl +V

  make
  make Precompiled.zip || make release_zip
  aws s3 cp *.zip s3://s3.hex.pm/builds/elixir/${1}.zip --acl public-read --cache-control "public, max-age=604800" --metadata "surrogate-key=builds"
  fastly_purge

  popd
}

# $1 = ref
function delete {
  aws s3 rm s3://s3.hex.pm/builds/elixir/${1}.zip
  fastly_purge
}

# $1 = ref
function otp {
  rm .tool-versions || true

  otp_version=$(elixir ${cwd}/../../scripts/elixir_to_otp.exs "$1")
  echo "Using OTP ${otp_version}"
  PATH=${HOME}/.asdf/installs/erlang/${otp_version}/bin:${PATH}
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
