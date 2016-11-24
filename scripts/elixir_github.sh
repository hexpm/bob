#!/bin/bash

# $1 = event
# $2 = ref

set -e -u

APPS=(eex elixir ex_unit iex logger mix)

function fastly_purge {
  curl \
    -X POST \
    -H "Fastly-Key: ${BOB_FASTLY_KEY}" \
    -H "Accept: application/json" \
    -H "Content-Length: 0" \
    "https://api.fastly.com/service/${BOB_FASTLY_SERVICE}/purge/${1}"
}

# $1 = ref
function build {
  git clone git://github.com/elixir-lang/elixir.git --quiet --branch ${1}

  pushd elixir

  otp $1
  erl +V
  make compile

  popd
}

function upload_build {
  pushd elixir

  make Precompiled.zip || make release_zip
  aws s3 cp *.zip s3://s3.hex.pm/builds/elixir/${1}.zip --acl public-read --cache-control "public,max-age=3600" --metadata '{"surrogate-key":"builds","surrogate-control":"public,max-age=604800"}'
  fastly_purge builds

  popd
}

function upload_docs {
  MIX_ARCHIVES=${cwd}/.mix
  PATH=${cwd}/elixir/bin:${PATH}
  elixir -v

  ex_doc_version=$(elixir ${cwd}/../../scripts/elixir_to_ex_doc.exs "$1")
  git clone git://github.com/elixir-lang/ex_doc.git --quiet --depth 1 --single-branch --branch ${ex_doc_version}

  mix local.hex --force
  mkdir docs
  cp ../../priv/logo.png docs/logo.png

  pushd ex_doc
  mix do deps.get, compile --no-elixir-version-check
  popd

  pushd elixir
  make docs

  tags=$(git tag)
  latest_version=$(elixir ${cwd}/../../scripts/latest_version.exs "${tags}")

  pushd doc
  for app in "${APPS[@]}"; do
    version=$(echo ${1} | sed 's/^v//g')
    aws s3 cp ${app} s3://hexdocs.pm/${app}/${version} --recursive --acl public-read --cache-control "public,max-age=3600" --metadata '{"surrogate-key":"docspage/${app}/${version}","surrogate-control":"public,max-age=604800"}'
    fastly_purge "docspage/${app}/${version}"

    if [ "${version}" == "${latest_version}" ]; then
      aws s3 cp ${app} s3://hexdocs.pm/${app} --recursive --acl public-read --cache-control "public,max-age=3600" --metadata '{"surrogate-key":"docspage/${app}","surrogate-control":"public,max-age=604800"}'
      fastly_purge "docspage/${app}"
    fi
  done

  popd
  popd
}

# $1 = ref
function delete {
  aws s3 rm s3://s3.hex.pm/builds/elixir/${1}.zip
  fastly_purge builds

  for app in "${APPS[@]}"; do
    version=$(echo ${1} | sed 's/^v//g')
    aws s3 rm s3://hexdocs.pm/${app}/${version} --recursive
    fastly_purge "docspage/${app}/${version}"
  done
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
    upload_build $2
    upload_docs $2
    ;;
  "delete")
    delete $2
    ;;
esac
