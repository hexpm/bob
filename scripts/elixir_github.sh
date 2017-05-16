#!/bin/bash

# $1 = event
# $2 = ref

set -e -u

APPS=(eex elixir ex_unit iex logger mix)
HEXPM=$BOB_FASTLY_SERVICE_HEXPM
HEXDOCS=$BOB_FASTLY_SERVICE_HEXDOCS

function fastly_purge {
  curl \
    -X POST \
    -H "Fastly-Key: ${BOB_FASTLY_KEY}" \
    -H "Accept: application/json" \
    -H "Content-Length: 0" \
    "https://api.fastly.com/service/${1}/purge/${2}"
}

# $1 = ref
function build {
  git clone git://github.com/elixir-lang/elixir.git --quiet --branch "${1}"

  pushd elixir

  otp "$1"
  erl +V
  make compile

  popd
}

function upload_build {
  pushd elixir

  make Precompiled.zip || make release_zip
  aws s3 cp *.zip "s3://s3.hex.pm/builds/elixir/${1}.zip" --acl public-read --cache-control "public,max-age=3600" --metadata '{"surrogate-key":"builds","surrogate-control":"public,max-age=604800"}'
  fastly_purge $HEXPM builds

  popd
}

function upload_docs {
  version=$(echo "${1}" | sed 's/^v//g')

  MIX_ARCHIVES="${cwd}/.mix"
  PATH="${cwd}/elixir/bin:${PATH}"
  elixir -v

  mix local.hex --force
  mkdir docs
  cp ../../priv/logo.png docs/logo.png

  git clone git://github.com/elixir-lang/ex_doc.git --quiet

  pushd ex_doc
  tags=$(git tag)
  latest_version=$(elixir ${scripts}/latest_version.exs "${tags}")
  ex_doc_version=$(elixir ${scripts}/elixir_to_ex_doc.exs "${1}" "${latest_version}")
  git checkout "${ex_doc_version}"
  mix do deps.get, compile --no-elixir-version-check
  popd

  pushd elixir
  sed -i -e 's/-n http:\/\/elixir-lang.org\/docs\/\$(CANONICAL)\/\$(2)\//-n https:\/\/hexdocs.pm\/\$(2)\/\$(CANONICAL)/g' Makefile
  sed -i -e 's/-a http:\/\/elixir-lang.org\/docs\/\$(CANONICAL)\/\$(2)\//-a https:\/\/hexdocs.pm\/\$(2)\/\$(CANONICAL)/g' Makefile
  CANONICAL="${version}" make docs

  tags=$(git tag)
  latest_version=$(elixir ${scripts}/latest_version.exs "${tags}")

  pushd doc
  for app in "${APPS[@]}"; do
    aws s3 cp "${app}" "s3://hexdocs.pm/${app}/${version}" --recursive --acl public-read --cache-control "public,max-age=3600" --metadata "{\"surrogate-key\":\"docspage/${app}/${version}\",\"surrogate-control\":\"public,max-age=604800\"}"
    fastly_purge $HEXDOCS "docspage/${app}/${version}"

    tar -czf "${app}-${version}.tar.gz" -C "${app}" .
    aws s3 cp "${app}-${version}.tar.gz" "s3://s3.hex.pm/docs/${app}-${version}.tar.gz" --acl public-read --cache-control "public,max-age=3600" --metadata "{\"surrogate-key\":\"docs/${app}-${version}\",\"surrogate-control\":\"public,max-age=604800\"}"
    fastly_purge $HEXPM "docs/${app}-${version}"
  done
  popd

  if [ "${version}" == "${latest_version}" ]; then
    rm -rf doc
    CANONICAL="" make docs

    pushd doc
    for app in "${APPS[@]}"; do
      aws s3 cp "${app}" "s3://hexdocs.pm/${app}" --recursive --acl public-read --cache-control "public,max-age=3600" --metadata "{\"surrogate-key\":\"docspage/${app}\",\"surrogate-control\":\"public,max-age=604800\"}"
      fastly_purge $HEXDOCS "docspage/${app}"
    done
    popd
  fi

  popd
}

# $1 = ref
function delete {
  aws s3 rm "s3://s3.hex.pm/builds/elixir/${1}.zip"

  for app in "${APPS[@]}"; do
    version=$(echo "${1}" | sed 's/^v//g')
    
    aws s3 rm "s3://s3.hex.pm/docs/${app}-${version}.tar.gz"
    fastly_purge $HEXPM builds

    aws s3 rm "s3://hexdocs.pm/${app}/${version}" --recursive
    fastly_purge $HEXDOCS "docspage/${app}/${version}"
  done
}

# $1 = ref
function otp {
  rm .tool-versions || true

  otp_version=$(elixir "${scripts}/elixir_to_otp.exs" "$1")
  echo "Using OTP ${otp_version}"
  PATH="${HOME}/.asdf/installs/erlang/${otp_version}/bin:${PATH}"
}

cwd=$(pwd)
scripts="${cwd}/../../scripts"

case "$1" in
  "push" | "create")
    build "$2"
    upload_build "$2"
    upload_docs "$2"
    ;;
  "delete")
    delete "$2"
    ;;
esac
